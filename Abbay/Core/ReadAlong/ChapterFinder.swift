//
//  ChapterFinder.swift
//  Abbay
//

import Foundation
import Observation

extension Notification.Name {
    /// A book's chapters changed: found in its audio, or removed again. `object` is the book's URL,
    /// `userInfo[ChapterFinder.chaptersKey]` its new `[ChapterModel]`. Posted on the main thread.
    static let bookChaptersDidChange = Notification.Name("abbay.bookChaptersDidChange")
}

/// Finds chapters for an imported book that has none (a plain MP3 has no chapter markers): read
/// along's speech engine transcribes the whole file on the device, and `ChapterHeadingDetector`
/// marks a chapter wherever the narrator reads out a heading ("Chapter Three", "Prologue").
///
/// Experimental, with a switch of its own in Settings (`AppSettings.findChaptersEnabled`, off by
/// default), independent of Read-along: offered only while it is on, on iOS 26 where the engine
/// runs, and turning it off stops a search (chapters already found stay). A search belongs to the app, not the player screen: closing the player
/// doesn't stop it, and the player shows its progress when it opens again. One search per book at a
/// time; tapping the pill again cancels it.
///
/// Chapters show **as they are found**, from the second heading on, so the book can be navigated
/// while the rest is searched. Each time they are saved like a file's own (`SaveChaptersUseCase`,
/// which keeps a chapter's resume offset where it starts where it did), so the chapter list,
/// Next/Previous chapter, chapter resume, Siri and CarPlay all use them, and the book is marked
/// (`AppSettings.hasFoundChapters`) so its chapter list offers to remove them. Stopping, or the
/// engine failing part way, keeps what was shown. Nothing found, or the file missing: a notice says
/// so and the book is left as it was.
///
/// The transcript the search makes is not kept: the player's read-along session may be writing the
/// same book's text, and two writers would overwrite each other's lines.
@MainActor
@Observable
final class ChapterFinder {
    /// How a search ended.
    enum Outcome: Equatable {
        /// It reached the end with chapters (shown as they were found).
        case found
        case noneFound
        case fileMissing
        case failed
        case cancelled
        /// The book left the library while it was searched: nothing to say.
        case bookGone
    }

    /// The new chapters in a `bookChaptersDidChange` notification.
    nonisolated static let chaptersKey = "chapters"

    /// Books being searched, by URL: how far through the audio, 0…1.
    private(set) var progress: [URL: Double] = [:]

    @ObservationIgnored private let transcriber: ReadAlongTranscribing?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private weak var playback: PlaybackCenter?
    @ObservationIgnored private let saveChapters: SaveChaptersUseCaseProtocol
    @ObservationIgnored private let notices: NoticeReporting
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let makeSource: (AudioModel) -> ReadAlongAudioSource
    @ObservationIgnored private let preferredLanguages: () -> [String]
    @ObservationIgnored private var tasks: [URL: Task<Void, Never>] = [:]
    /// What each search has shown so far, as the detector gave it: a new detection that is the
    /// same publishes nothing.
    @ObservationIgnored private var published: [URL: [ChapterModel]] = [:]

    /// Built by `ReadAlongCenter`, off the main actor's checks like it. `makeSource` and
    /// `preferredLanguages` are for tests.
    nonisolated init(
        transcriber: ReadAlongTranscribing?,
        settings: AppSettings,
        playback: PlaybackCenter?,
        saveChapters: SaveChaptersUseCaseProtocol = SaveChaptersUseCase(),
        notices: NoticeReporting = NoticeCenter.shared,
        notificationCenter: NotificationCenter = .default,
        makeSource: @escaping (AudioModel) -> ReadAlongAudioSource = { ReadAlongAudioSource.make(for: $0) },
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.transcriber = transcriber
        self.settings = settings
        self.playback = playback
        self.saveChapters = saveChapters
        self.notices = notices
        self.notificationCenter = notificationCenter
        self.makeSource = makeSource
        self.preferredLanguages = preferredLanguages
        Task { @MainActor [weak self] in self?.observeEnabled() }
    }

    // MARK: - What the player offers

    /// Whether the player offers *Find chapters* for the book: an imported book without chapters,
    /// with the experimental switch on where the engine runs.
    func offers(_ book: AudioModel) -> Bool {
        transcriber != nil && settings.findChaptersEnabled && !book.isLibriVox && book.chapters.isEmpty
            && book.url != nil
    }

    /// How far the book's search is, 0…1; nil when it isn't being searched.
    func progress(of book: AudioModel) -> Double? {
        book.url.flatMap { progress[$0] }
    }

    /// Whether the book's chapters were found in its audio, so its chapter list offers to remove
    /// them.
    func hasFoundChapters(_ book: AudioModel) -> Bool {
        !book.chapters.isEmpty && settings.hasFoundChapters(for: book.url)
    }

    // MARK: - Actions

    func find(_ book: AudioModel) {
        guard offers(book), let url = book.url, tasks[url] == nil, let transcriber else { return }
        progress[url] = 0
        let source = makeSource(book)
        let title = Notice.title(of: book)
        tasks[url] = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.search(book, url: url, source: source, transcriber: transcriber)
            self.finish(url: url, title: title, outcome: outcome)
        }
    }

    /// Stops the search. Chapters it already showed stay (and can be removed).
    func cancel(_ book: AudioModel) {
        guard let url = book.url else { return }
        tasks[url]?.cancel()
        tasks[url] = nil
        progress[url] = nil
        published[url] = nil
    }

    /// The found chapters go: the book is as it was imported.
    func removeFoundChapters(_ book: AudioModel) {
        guard let url = book.url, settings.hasFoundChapters(for: url), progress[url] == nil else { return }
        settings.setHasFoundChapters(false, for: url)
        guard let saved = saveChapters.execute([], bookURL: url) else { return }
        changed(saved, url: url)
    }

    // MARK: - Searching

    /// Where language detection listens: a little way in, past an opening of music or credits.
    static func detectionTime(duration: Double) -> Double {
        max(min(duration * 0.1, 300), 0)
    }

    private func search(
        _ book: AudioModel,
        url: URL,
        source: ReadAlongAudioSource,
        transcriber: ReadAlongTranscribing
    ) async -> Outcome {
        guard source.isOnDevice(at: 0) else { return .fileMissing }
        let supported = await transcriber.supportedLocales()
        guard !Task.isCancelled else { return .cancelled }
        let resolver = ReadAlongLanguageResolver(
            transcriber: transcriber,
            settings: settings,
            preferredLanguages: preferredLanguages
        )
        let resolved = await resolver.resolve(
            url: url,
            supported: supported,
            source: source,
            at: Self.detectionTime(duration: book.duration)
        ) { !Task.isCancelled }
        let locale: String
        switch resolved {
        case .resolved(let resolvedLocale): locale = resolvedLocale
        case .audioMissing: return .fileMissing
        case .cancelled: return .cancelled
        }

        if let failure = await installModel(locale, transcriber: transcriber) { return failure }
        return await transcribe(book, url: url, source: source, locale: locale, transcriber: transcriber)
    }

    /// Nil once the language's model is on the device (downloaded first if iOS offers it); else how
    /// the search ends.
    private func installModel(_ locale: String, transcriber: ReadAlongTranscribing) async -> Outcome? {
        switch await transcriber.modelStatus(locale: locale) {
        case .unsupported:
            return .failed
        case .downloadable:
            do {
                try await transcriber.installModel(locale: locale)
            } catch {
                return Task.isCancelled ? .cancelled : .failed
            }
        case .installed:
            break
        }
        return Task.isCancelled ? .cancelled : nil
    }

    /// Transcribes the whole book from its start, reporting progress as the audio is covered, and
    /// shows the chapters as they are heard: once two headings are in, and again at each heading
    /// after (the last chapter found runs to the end of the book until the next one is heard). The
    /// detector runs again only after a chunk that may hold a heading, or the one after it (a
    /// heading's number can come in the next).
    private func transcribe(
        _ book: AudioModel,
        url: URL,
        source: ReadAlongAudioSource,
        locale: String,
        transcriber: ReadAlongTranscribing
    ) async -> Outcome {
        var lines: [ReadAlongLine] = []
        var detectNext = false
        do {
            for try await chunk in transcriber.transcribe(source, from: 0, locale: locale) {
                guard !Task.isCancelled else { return .cancelled }
                lines += chunk.lines
                if book.duration > 0 {
                    progress[url] = min(max(chunk.covered.end / book.duration, 0), 1)
                }
                let mayHoldHeading = chunk.lines.contains { line in
                    line.words.contains { ChapterHeadingDetector.mayStartHeading($0.text) }
                }
                if mayHoldHeading || detectNext, !publishDetected(in: lines, book: book, url: url) {
                    return .bookGone
                }
                detectNext = mayHoldHeading
            }
        } catch {
            return Task.isCancelled ? .cancelled : .failed
        }
        guard !Task.isCancelled else { return .cancelled }
        guard publishDetected(in: lines, book: book, url: url) else { return .bookGone }
        return published[url]?.isEmpty == false ? .found : .noneFound
    }

    /// Runs the detector over the lines so far and shows its chapters if they changed. False when
    /// the book has no row to save them to any more.
    private func publishDetected(in lines: [ReadAlongLine], book: AudioModel, url: URL) -> Bool {
        let chapters = ChapterHeadingDetector.chapters(
            in: lines,
            duration: book.duration,
            openingTitle: Localizable.chapterOpening.localized
        )
        guard !chapters.isEmpty, chapters != published[url] else { return true }
        guard let saved = saveChapters.execute(chapters, bookURL: url) else { return false }
        published[url] = chapters
        settings.setHasFoundChapters(true, for: url)
        changed(saved, url: url)
        return true
    }

    private func finish(url: URL, title: String, outcome: Outcome) {
        // A cancelled search was already cleared by `cancel` (or the off switch), and a new one
        // may have started since.
        guard outcome != .cancelled, !Task.isCancelled else { return }
        tasks[url] = nil
        progress[url] = nil
        published[url] = nil
        switch outcome {
        case .found, .bookGone:
            // Already shown as found; a deleted book has nothing to say.
            break
        case .noneFound:
            notices.report(.noChaptersFound)
        case .fileMissing:
            notices.report(.fileMissing(title: title))
        case .failed:
            // Chapters already shown stay.
            notices.report(.chapterSearchFailed)
        case .cancelled:
            break
        }
    }

    /// Hands the new chapters to the player (if the book is loaded) and to the screens.
    private func changed(_ chapters: [ChapterModel], url: URL) {
        playback?.replaceChapters(chapters, ofBookAt: url)
        notificationCenter.post(name: .bookChaptersDidChange, object: url, userInfo: [Self.chaptersKey: chapters])
    }

    // MARK: - Switched off

    private func observeEnabled() {
        withObservationTracking {
            _ = settings.findChaptersEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.enabledChanged() }
        }
    }

    private func enabledChanged() {
        if !settings.findChaptersEnabled {
            for task in tasks.values { task.cancel() }
            tasks = [:]
            progress = [:]
            published = [:]
        }
        observeEnabled()
    }
}

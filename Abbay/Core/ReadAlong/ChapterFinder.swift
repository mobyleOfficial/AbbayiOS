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
/// How far the transcription got is saved with the book (`AppSettings.chapterSearchCoverage`): short
/// of the book's end, the chapter list offers *Continue finding* (#316), which picks up from the
/// start of the last chapter found.
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
    /// How far each running search has transcribed, in book seconds, and how far that was when it
    /// was last saved (`AppSettings.chapterSearchCoverage`).
    @ObservationIgnored private var covered: [URL: Double] = [:]
    @ObservationIgnored private var savedCoverage: [URL: Double] = [:]

    /// Coverage is saved at least this often, in seconds of audio, so a killed app loses little.
    static let coverageSaveInterval = 120.0
    /// Coverage this close to the book's end is the whole book.
    static let wholeBookTolerance = 1.0

    /// Where a search starts, and the chapters it builds on: none from the start; the chapters
    /// found so far when it continues from the start of the last one (#316). With the book's audio.
    private struct Run {
        let from: Double
        let base: [ChapterModel]
        var source = ReadAlongAudioSource(segments: [], isLibriVox: false)
    }

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

    /// How much of the book its chapter search has transcribed, 0…1, when that is short of the
    /// whole book (a search stopped, failed or cut off by the app ending); nil when the whole audio
    /// was analysed, or it isn't known (owner: offer to continue exactly when the transcription
    /// didn't analyse the whole audio).
    func searchedFraction(of book: AudioModel) -> Double? {
        guard hasFoundChapters(book), book.duration > 0,
              let coverage = settings.chapterSearchCoverage(for: book.url),
              coverage < book.duration - Self.wholeBookTolerance
        else { return nil }
        return min(max(coverage / book.duration, 0), 1)
    }

    /// Whether the chapter list offers *Continue finding*: found chapters, a search that didn't
    /// cover the whole book, none running, and the switch on where the engine runs.
    func canContinue(_ book: AudioModel) -> Bool {
        transcriber != nil && settings.findChaptersEnabled && progress(of: book) == nil
            && searchedFraction(of: book) != nil
    }

    // MARK: - Actions

    func find(_ book: AudioModel) {
        guard offers(book) else { return }
        start(book, run: Run(from: 0, base: []))
    }

    /// Picks the search up from the start of the last chapter found, which ran to the end of the
    /// book because the next heading hadn't been heard: a heading cut off where it stopped is heard
    /// whole, and the chapters before it stay as they are.
    func continueFinding(_ book: AudioModel) {
        guard canContinue(book), let last = book.chapters.last else { return }
        start(book, run: Run(from: last.startTime, base: book.chapters))
    }

    private func start(_ book: AudioModel, run: Run) {
        guard let url = book.url, tasks[url] == nil, let transcriber else { return }
        var run = run
        run.source = makeSource(book)
        progress[url] = book.duration > 0 ? min(max(run.from / book.duration, 0), 1) : 0
        published[url] = run.base
        covered[url] = run.from
        savedCoverage[url] = settings.chapterSearchCoverage(for: url)
        let title = Notice.title(of: book)
        tasks[url] = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.search(book, url: url, transcriber: transcriber, run: run)
            self.finish(url: url, title: title, outcome: outcome)
        }
    }

    /// Stops the search. Chapters it already showed stay (and can be removed), with how far it got,
    /// so it can be continued.
    func cancel(_ book: AudioModel) {
        guard let url = book.url else { return }
        tasks[url]?.cancel()
        end(url)
    }

    /// Forgets a search that has ended, saving how far it got.
    private func end(_ url: URL) {
        saveCoverage(url, force: true)
        tasks[url] = nil
        progress[url] = nil
        published[url] = nil
        covered[url] = nil
        savedCoverage[url] = nil
    }

    /// Saves how far the search has transcribed, for books with chapters to show for it: at least
    /// every `coverageSaveInterval` of audio, and whenever `force`d (a new chapter, the end).
    private func saveCoverage(_ url: URL, force: Bool = false) {
        guard let seconds = covered[url], settings.hasFoundChapters(for: url) else { return }
        let last = savedCoverage[url] ?? 0
        guard seconds > last, force || seconds - last >= Self.coverageSaveInterval else { return }
        settings.setChapterSearchCoverage(seconds, for: url)
        savedCoverage[url] = seconds
    }

    /// The found chapters go: the book is as it was imported.
    func removeFoundChapters(_ book: AudioModel) {
        guard let url = book.url, settings.hasFoundChapters(for: url), progress[url] == nil else { return }
        settings.setHasFoundChapters(false, for: url)
        settings.setChapterSearchCoverage(nil, for: url)
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
        transcriber: ReadAlongTranscribing,
        run: Run
    ) async -> Outcome {
        let source = run.source
        guard source.isOnDevice(at: run.from) else { return .fileMissing }
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
        return await transcribe(book, url: url, locale: locale, transcriber: transcriber, run: run)
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

    /// Transcribes the book from the run's start to its end, reporting progress as the audio is
    /// covered (and saving how far, `saveCoverage`), and
    /// shows the chapters as they are heard: once two headings are in, and again at each heading
    /// after (the last chapter found runs to the end of the book until the next one is heard). The
    /// detector runs again only after a chunk that may hold a heading, or the one after it (a
    /// heading's number can come in the next).
    private func transcribe(
        _ book: AudioModel,
        url: URL,
        locale: String,
        transcriber: ReadAlongTranscribing,
        run: Run
    ) async -> Outcome {
        var lines: [ReadAlongLine] = []
        var detectNext = false
        do {
            for try await chunk in transcriber.transcribe(run.source, from: run.from, locale: locale) {
                guard !Task.isCancelled else { return .cancelled }
                lines += chunk.lines
                covered[url] = max(covered[url] ?? 0, chunk.covered.end)
                if book.duration > 0 {
                    progress[url] = min(max(chunk.covered.end / book.duration, 0), 1)
                }
                let mayHoldHeading = chunk.lines.contains { line in
                    line.words.contains { ChapterHeadingDetector.mayStartHeading($0.text) }
                }
                if mayHoldHeading || detectNext, !publishDetected(in: lines, book: book, url: url, run: run) {
                    return .bookGone
                }
                detectNext = mayHoldHeading
                saveCoverage(url)
            }
        } catch {
            return Task.isCancelled ? .cancelled : .failed
        }
        guard !Task.isCancelled else { return .cancelled }
        guard publishDetected(in: lines, book: book, url: url, run: run) else { return .bookGone }
        // The stream ended at the end of the audio: the whole book has been analysed.
        covered[url] = max(covered[url] ?? 0, book.duration)
        return published[url]?.isEmpty == false ? .found : .noneFound
    }

    /// Runs the detector over the lines so far (from the start, or after the chapters a continued
    /// run builds on) and shows its chapters if they changed. False when the book has no row to
    /// save them to any more.
    private func publishDetected(in lines: [ReadAlongLine], book: AudioModel, url: URL, run: Run) -> Bool {
        let chapters = run.base.isEmpty
            ? ChapterHeadingDetector.chapters(
                in: lines,
                duration: book.duration,
                openingTitle: Localizable.chapterOpening.localized
            )
            : ChapterHeadingDetector.extending(run.base, with: lines, duration: book.duration)
        guard !chapters.isEmpty, chapters != published[url] else { return true }
        guard let saved = saveChapters.execute(chapters, bookURL: url) else { return false }
        published[url] = chapters
        settings.setHasFoundChapters(true, for: url)
        changed(saved, url: url)
        saveCoverage(url, force: true)
        return true
    }

    private func finish(url: URL, title: String, outcome: Outcome) {
        // A cancelled search was already cleared by `cancel` (or the off switch), and a new one
        // may have started since.
        guard outcome != .cancelled, !Task.isCancelled else { return }
        // A deleted book keeps no record of its search.
        if outcome == .bookGone { covered[url] = nil }
        end(url)
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
            for (url, task) in tasks {
                task.cancel()
                end(url)
            }
        }
        observeEnabled()
    }
}

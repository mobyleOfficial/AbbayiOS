//
//  ReadAlongSession.swift
//  Abbay
//

import Foundation
import Observation

/// What the player's read-along square says.
enum ReadAlongState: Equatable {
    /// Detecting the language, or no line yet at the shown time.
    case preparing
    /// Downloading the speech model for this locale id.
    case downloadingModel(String)
    /// iOS can't transcribe this locale id.
    case unsupported(String)
    /// The LibriVox chapter at the shown time isn't on the device.
    case needsDownload
    /// The imported file isn't on the device.
    case fileMissing
    case failed
    /// The shown time is covered: by a line, or by silence.
    case ready
}

/// One book's read-along while its text is on screen: resolves the language, has the model
/// downloaded when needed, says when the audio isn't here, loads what was saved and transcribes
/// from the shown time, saving as it goes.
///
/// Transcription runs only while the text is shown (`show` until `stop`), from the shown time
/// ahead of playback. At about 70× real time there is nothing to gain from running further ahead:
/// a run starts where the text is uncovered, or at the end of the covered stretch once the shown
/// time is within `lookahead` of it, and a seek out of a run's reach restarts it there.
///
/// One run at a time, as one `Task`, cancelled whenever the session retargets. Two runs never
/// transcribe the same audio: a run started at a seek cuts phrases differently from an earlier one,
/// so both sets of lines would be kept side by side. A run never starts inside covered audio, drops
/// incoming lines that start in audio covered before it began (the old lines win), and stops once
/// it reaches that audio.
@MainActor
@Observable
final class ReadAlongSession {
    /// How close to the end of the covered stretch the shown time gets before the next run starts,
    /// and how far past a run's progress a seek can land and still be left to that run.
    nonisolated static let lookahead = 60.0
    /// Seconds of audio each candidate language transcribes for detection.
    static let detectionSeconds = 20.0

    private(set) var state: ReadAlongState = .preparing
    private(set) var transcript: ReadAlongTranscript?
    /// The locale id in use.
    private(set) var language: String?
    /// The locales iOS can transcribe, for the language picker.
    private(set) var choices: [String] = []

    /// A transcription run in progress.
    private struct Run {
        let id: Int
        let task: Task<Void, Never>
        let start: Double
        /// How far it has covered.
        var frontier: Double

        /// Whether the run will cover `time` shortly, so a seek there needs no new run.
        func reaches(_ time: Double) -> Bool {
            start <= time && time <= frontier + ReadAlongSession.lookahead
        }
    }

    private enum RunEnd {
        /// It covered all the audio on the device from its start.
        case finished
        /// It reached audio an earlier run covered.
        case enteredCovered
        case failed
    }

    @ObservationIgnored private let transcriber: ReadAlongTranscribing?
    @ObservationIgnored private let store: ReadAlongStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let makeSource: (AudioModel) -> ReadAlongAudioSource
    @ObservationIgnored private let preferredLanguages: () -> [String]
    @ObservationIgnored private let saveInterval: Duration

    @ObservationIgnored private var book: AudioModel?
    @ObservationIgnored private var source: ReadAlongAudioSource?
    @ObservationIgnored private var shownTime = 0.0
    /// Between `show` and `stop`. Nothing runs, detects or downloads while the text is hidden, even
    /// when the time or the downloads change: those only matter once it is shown again.
    @ObservationIgnored private var isShown = false
    /// Language resolved, model installed, saved text loaded: runs can start.
    @ObservationIgnored private var isPrepared = false
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var run: Run?
    @ObservationIgnored private var runCount = 0
    /// Bumped on every retarget, so work begun for an earlier book or language drops its result.
    @ObservationIgnored private var generation = 0
    /// A run or a model download failed: nothing restarts by itself until the next `show`.
    @ObservationIgnored private var hasFailed = false
    /// The span the last run that ran out of audio started and ended in. Starting another run in it
    /// would read the same nothing again, on every tick.
    @ObservationIgnored private var exhausted: ReadAlongSpan?
    @ObservationIgnored private var hasUnsavedText = false
    @ObservationIgnored private var lastSave: ContinuousClock.Instant?

    /// `makeSource`, `preferredLanguages` and `saveInterval` are for tests; the defaults are the
    /// app's.
    init(
        transcriber: ReadAlongTranscribing?,
        store: ReadAlongStore,
        settings: AppSettings,
        makeSource: @escaping (AudioModel) -> ReadAlongAudioSource = { ReadAlongAudioSource.make(for: $0) },
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
        saveInterval: Duration = .seconds(2)
    ) {
        self.transcriber = transcriber
        self.store = store
        self.settings = settings
        self.makeSource = makeSource
        self.preferredLanguages = preferredLanguages
        self.saveInterval = saveInterval
        observeEnabled()
    }

    // MARK: - Driving

    /// The text is on screen for `book` at `time`: start, or retarget. The same book at a time
    /// already covered, or that the current run is about to cover, restarts nothing.
    func show(_ book: AudioModel, at time: Double) {
        guard settings.readAlongEnabled else { return }
        guard transcriber != nil, book.url != nil else {
            state = .failed
            return
        }
        if let current = self.book, current.url == book.url {
            isShown = true
            shownTime = time
            if hasFailed || (!isPrepared && preparation == nil && !isWaitingForAudio) {
                hasFailed = false
                prepare()
            } else {
                evaluate()
            }
            return
        }
        stop()
        reset()
        self.book = book
        source = makeSource(book)
        shownTime = time
        isShown = true
        prepare()
    }

    /// The shown time moved: playback, a seek, or the scrubber.
    func timeChanged(_ time: Double) {
        guard book != nil, isShown, settings.readAlongEnabled else { return }
        shownTime = time
        evaluate()
    }

    /// The book's downloads changed: a chapter may have arrived (or gone). While the text is hidden
    /// the new files are only noted; the next `show` acts on them.
    func downloadsChanged(_ book: AudioModel) {
        guard let current = self.book, current.url == book.url, settings.readAlongEnabled else { return }
        self.book = book
        source = makeSource(book)
        exhausted = nil
        evaluate()
    }

    /// The user picked a language: kept for the book, and its text starts over in it (at the next
    /// `show`, if the text is hidden).
    func setLanguage(_ locale: String) {
        guard let url = book?.url, locale != language else { return }
        settings.setReadAlongLanguage(locale, for: url)
        cancelWork()
        hasUnsavedText = false
        store.delete(bookURL: url)
        transcript = nil
        language = locale
        isPrepared = false
        hasFailed = false
        exhausted = nil
        state = .preparing
        prepare()
    }

    /// The text left the screen: the run stops, and what it transcribed is saved.
    func stop() {
        isShown = false
        cancelWork()
        saveNow()
    }
}

// MARK: - Preparing

extension ReadAlongSession {
    private var isWaitingForAudio: Bool {
        state == .needsDownload || state == .fileMissing
    }

    private var missingAudioState: ReadAlongState {
        source?.isLibriVox == true ? .needsDownload : .fileMissing
    }

    private func reset() {
        book = nil
        source = nil
        transcript = nil
        language = nil
        isPrepared = false
        hasFailed = false
        exhausted = nil
        hasUnsavedText = false
        lastSave = nil
        isShown = false
        state = .preparing
    }

    private func cancelWork() {
        generation += 1
        preparation?.cancel()
        preparation = nil
        cancelRun()
    }

    private func prepare() {
        guard isShown, let transcriber, let book, let url = book.url else { return }
        preparation?.cancel()
        generation += 1
        let generation = generation
        state = .preparing
        preparation = Task { [weak self] in
            await self?.prepare(book, url: url, transcriber: transcriber, generation: generation)
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation && !Task.isCancelled
    }

    private func prepare(_ book: AudioModel, url: URL, transcriber: ReadAlongTranscribing, generation: Int) async {
        let supported = await transcriber.supportedLocales()
        guard isCurrent(generation) else { return }
        choices = supported

        let resolved: String?
        if let language {
            resolved = language
        } else {
            resolved = await resolveLanguage(
                url: url,
                supported: supported,
                transcriber: transcriber,
                generation: generation
            )
        }
        guard isCurrent(generation), let locale = resolved else {
            if isCurrent(generation) { preparation = nil }
            return
        }
        language = locale

        switch await transcriber.modelStatus(locale: locale) {
        case .unsupported:
            guard isCurrent(generation) else { return }
            state = .unsupported(locale)
            preparation = nil
            return
        case .downloadable:
            guard isCurrent(generation) else { return }
            state = .downloadingModel(locale)
            do {
                try await transcriber.installModel(locale: locale)
            } catch {
                guard isCurrent(generation) else { return }
                hasFailed = true
                state = .failed
                preparation = nil
                return
            }
        case .installed:
            break
        }
        guard isCurrent(generation) else { return }

        if let saved = store.load(bookURL: url), saved.language == locale {
            transcript = saved
        } else {
            transcript = ReadAlongTranscript(language: locale)
        }
        isPrepared = true
        preparation = nil
        evaluate()
    }

    /// The book's language: its own setting (a bare code from LibriVox is matched to a supported
    /// locale and saved back as one), else detected among the installed models, else the in-app
    /// language. Detection reads the audio, so without it this waits (nil) like a run would. The
    /// result is saved for the book, so a book is detected once and its text stays in one language.
    private func resolveLanguage(
        url: URL,
        supported: [String],
        transcriber: ReadAlongTranscribing,
        generation: Int
    ) async -> String? {
        if let stored = settings.readAlongLanguage(for: url) {
            guard Self.isBareCode(stored) else { return stored }
            let installed = await transcriber.installedLocales()
            guard isCurrent(generation) else { return nil }
            guard let locale = ReadAlongLanguage.locale(
                forLanguageCode: stored,
                in: supported,
                installed: installed,
                preferredRegion: preferredRegion(for: stored)
            ) else { return stored }
            settings.setReadAlongLanguage(locale, for: url)
            return locale
        }

        guard let source, source.isOnDevice(at: shownTime) else {
            state = missingAudioState
            return nil
        }
        let time = shownTime
        let installed = await transcriber.installedLocales()
        guard isCurrent(generation) else { return nil }
        let candidates = ReadAlongLanguage.candidates(
            appLanguage: settings.language.languageCode,
            preferred: preferredLanguages(),
            installed: installed
        )
        var scores: [String: Double] = [:]
        for candidate in candidates {
            // A locale the engine can't score (its model isn't usable) just has no score.
            let score = try? await transcriber.confidence(
                source,
                from: time,
                seconds: Self.detectionSeconds,
                locale: candidate
            )
            guard isCurrent(generation) else { return nil }
            scores[candidate] = score
        }
        let locale = ReadAlongLanguage.best(scores) ?? appLanguageLocale(in: supported, installed: installed)
        settings.setReadAlongLanguage(locale, for: url)
        return locale
    }

    /// The in-app language's locale among the supported ones, chosen as `ReadAlongLanguage.locale`
    /// does (the device's region, an installed model, the likely region); the language id itself
    /// (which the model check then reports as unsupported) when iOS has none.
    private func appLanguageLocale(in supported: [String], installed: [String]) -> String {
        let id = settings.language.languageCode ?? AbbayBundle.locale.identifier
        let language = Locale(identifier: id).language
        let code = language.languageCode?.identifier ?? "en"
        let region = language.region?.identifier ?? preferredRegion(for: code)
        let locale = ReadAlongLanguage.locale(
            forLanguageCode: code,
            in: supported,
            installed: installed,
            preferredRegion: region
        )
        return locale ?? id.replacingOccurrences(of: "_", with: "-")
    }

    /// The region of the first device language in `code`: "pt" on a Brazilian device is "BR".
    private func preferredRegion(for code: String) -> String? {
        preferredLanguages().lazy
            .map { Locale(identifier: $0).language }
            .first { $0.languageCode?.identifier == code.lowercased() && $0.region != nil }?
            .region?.identifier
    }

    private static func isBareCode(_ id: String) -> Bool {
        !id.contains("-") && !id.contains("_")
    }

}

// MARK: - Deciding and running

extension ReadAlongSession {
    /// Brings the state and the run in line with the shown time.
    private func evaluate() {
        guard isShown, let source else { return }
        guard isPrepared, let transcript else {
            // Detection waits for the audio: it may be here now.
            if preparation == nil, isWaitingForAudio, source.isOnDevice(at: shownTime) {
                prepare()
            }
            return
        }
        guard !hasFailed else { return }
        let time = shownTime
        if isPastTheEnd(time) {
            state = .ready
            return
        }
        if let span = transcript.covered.first(where: { $0.start <= time && time < $0.end }) {
            state = .ready
            if span.end - time < Self.lookahead, canRun(from: span.end), run?.reaches(span.end) != true {
                startRun(at: span.end)
            }
            return
        }
        if run?.reaches(time) == true {
            state = .preparing
            return
        }
        guard source.isOnDevice(at: time) else {
            cancelRun()
            state = missingAudioState
            return
        }
        guard canRun(from: time) else {
            state = .failed
            return
        }
        state = .preparing
        startRun(at: time)
    }

    private func isPastTheEnd(_ time: Double) -> Bool {
        guard let duration = book?.duration, duration > 0 else { return false }
        return time >= duration
    }

    private func canRun(from time: Double) -> Bool {
        guard let source, source.isOnDevice(at: time), !isPastTheEnd(time) else { return false }
        if let exhausted, exhausted.start <= time, time <= exhausted.end { return false }
        return true
    }

    private func startRun(at start: Double) {
        cancelRun()
        guard isShown, let transcriber, let source, let language, let transcript else { return }
        runCount += 1
        let id = runCount
        // Audio an earlier run covered: its lines win, and this run stops on reaching it.
        let earlier = transcript.covered
        let limit = earlier.first { $0.start > start }?.start
        let stream = transcriber.transcribe(source, from: start, locale: language)
        let task = Task { [weak self] in
            do {
                for try await chunk in stream {
                    guard let self, !Task.isCancelled, self.run?.id == id else { return }
                    let reachedEarlier = self.receive(chunk, earlier: earlier, limit: limit)
                    if reachedEarlier {
                        self.endRun(id, .enteredCovered)
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                self?.endRun(id, .finished)
            } catch {
                guard !Task.isCancelled else { return }
                self?.endRun(id, .failed)
            }
        }
        run = Run(id: id, task: task, start: start, frontier: start)
    }

    private func cancelRun() {
        run?.task.cancel()
        run = nil
    }

    /// Adds a chunk; true once the run has reached audio an earlier run covered.
    private func receive(_ chunk: ReadAlongChunk, earlier: [ReadAlongSpan], limit: Double?) -> Bool {
        guard var transcript else { return false }
        let fresh = chunk.lines.filter { line in
            !earlier.contains { $0.start <= line.start && line.start < $0.end }
        }
        transcript.add(fresh, covering: chunk.covered)
        self.transcript = transcript
        hasUnsavedText = true
        if let frontier = run?.frontier {
            run?.frontier = max(frontier, chunk.covered.end)
        }
        saveIfDue()
        let reachedEarlier = limit.map { chunk.covered.end >= $0 } ?? false
        if !reachedEarlier {
            evaluate()
        }
        return reachedEarlier
    }

    private func endRun(_ id: Int, _ end: RunEnd) {
        guard let ended = run, ended.id == id else { return }
        run = nil
        saveNow()
        switch end {
        case .failed:
            hasFailed = true
            state = .failed
        case .finished:
            exhausted = ReadAlongSpan(start: ended.start, end: ended.frontier)
            evaluate()
        case .enteredCovered:
            // Explicit, so the engine stops reading now rather than when the stream is let go.
            ended.task.cancel()
            evaluate()
        }
    }

}

// MARK: - Saving and Read-along off

extension ReadAlongSession {
    /// Within a run: at most every `saveInterval`, so a fast run doesn't rewrite the file per chunk.
    private func saveIfDue() {
        // A cancelled run belongs to a book or language that has moved on; the session saved for it
        // when it moved.
        guard !Task.isCancelled else { return }
        if let lastSave, ContinuousClock.now - lastSave < saveInterval { return }
        saveNow()
    }

    /// Read-along turned off deletes every transcript: a save after that would bring the folder
    /// back, so every save checks the setting first.
    private func saveNow() {
        guard hasUnsavedText, settings.readAlongEnabled, let url = book?.url, let transcript else { return }
        store.save(transcript, bookURL: url)
        hasUnsavedText = false
        lastSave = .now
    }

    /// Turning Read-along off stops everything at once, and forgets the text it deleted.
    private func observeEnabled() {
        withObservationTracking {
            _ = settings.readAlongEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.enabledChanged() }
        }
    }

    private func enabledChanged() {
        if !settings.readAlongEnabled {
            cancelWork()
            reset()
        }
        observeEnabled()
    }
}

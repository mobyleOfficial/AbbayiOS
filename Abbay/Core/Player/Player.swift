//
//  Player.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 24/06/23.
//

import AVFoundation
import Combine
import os
import UIKit

protocol PlayerProtocol {
    var url: URL? { get }
    var currentTime: Double { get }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { get }
    var playUrlSubjectPublisher: AnyPublisher<AudioModel, Never> { get }
    /// Whether the player is playing (or buffering towards it), on the main queue, without
    /// duplicates. See `Player.isPlaying(status:reason:)`.
    /// Unlike the time publisher it also fires on a pause, which stops the ticks.
    var isPlayingPublisher: AnyPublisher<Bool, Never> { get }

    func play(_ model: inout AudioModel)
    func pause()
    func forward(withSeconds seconds: Double)
    func backward(withSeconds seconds: Double)
    /// Whether `url` is loaded and playing, by the same rule as `isPlayingPublisher`.
    func isPlaying(_ url: URL?) -> Bool
    func seek(_ seconds: Double)
    func cleanup()
    /// Stops and forgets the loaded book (it was deleted), so `url` becomes nil. Unlike `cleanup`,
    /// which runs at termination, the player stays usable: the next `play` loads normally.
    func unload()
    func skipToNextChapter()
    func skipToPreviousChapter()
    /// Plays a chapter of the loaded book from where it was left (#299); the chapter already
    /// playing just keeps playing.
    @discardableResult
    func playChapter(at index: Int) -> Bool
    /// Where `playChapter(at:)` would start chapter `index` of `book`, for loading a book there.
    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double
    /// The loaded book's speed; normal speed when nothing is loaded.
    var playbackRate: Double { get }
    /// Sets the loaded book's speed, saves it for that book, and applies it at once when playing.
    /// It holds across pause and resume, seeks and chapter files.
    func setPlaybackRate(_ rate: Double)
    /// Abbay's own volume, 0–1, under the system volume. One level for every book.
    var volume: Double { get }
    /// Sets and saves Abbay's volume, applied at once whether playing or not.
    func setVolume(_ volume: Double)
    /// The loaded book got new chapters (or lost them): found in its audio, or removed again. Only
    /// an imported single-file book's chapters can change; anything else is ignored.
    func replaceChapters(_ chapters: [ChapterModel], ofBookAt url: URL)
}

/// For players with no speed or volume control, or saved chapter positions (test doubles that
/// predate them).
extension PlayerProtocol {
    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double {
        book.chapters.indices.contains(index) ? book.chapters[index].resumeTime : 0
    }

    var playbackRate: Double { PlaybackSpeed.normal }

    func setPlaybackRate(_ rate: Double) {}

    var volume: Double { BookVolume.full }

    func setVolume(_ volume: Double) {}

    func replaceChapters(_ chapters: [ChapterModel], ofBookAt url: URL) {}
}

final class Player: PlayerProtocol {
    // MARK: - Properties
    // A queue player for every book: single-file books only ever hold one item, multi-file
    // (LibriVox) books hold the current chapter's file plus the next one for gapless playback.
    private let player = AVQueuePlayer()
    private var model: AudioModel?
    /// Update-only: a book deleted while it's loaded here must not be re-inserted.
    private let savePlaybackPositionUseCase: SavePlaybackPositionUseCaseProtocol
    private let chapterResume: LoadChapterResumeUseCaseProtocol
    /// Notes chapters played through to their end, which then start over (#299).
    private let chapterCompletion = ChapterCompletion()
    private let intentDonor: IntentDonorProtocol
    private let librarySnapshotWriter: LibrarySnapshotWriterProtocol
    private let audioSessionActivator: AudioSessionActivatorProtocol
    private let bookmarkProvider: BookmarkProviderProtocol
    private let chapterPrioritizer: ChapterPrioritizing
    private let downloadsRoot: URL
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let noticeReporter: NoticeReporting
    /// Tells "can't stream this chapter while offline" from any other chapter failure.
    private let networkPath: NetworkPathProviding
    /// When the position was last written, so a playing book saves at most every
    /// `positionSaveInterval`. Restarts on every save and on loading a book.
    private var lastPositionSave: Date?
    private var notificationObservers: [NSObjectProtocol] = []
    private let speeds: PlaybackSpeedStoring
    private let volumes: PlaybackVolumeStoring
    /// Past 100%: a tap on every item multiplies the samples (#297).
    private let boost = VolumeBoost()
    private let lastPlayed: LastPlayedStore
    private let launchState: LaunchStateFlag
    /// Donations on pause, on an interruption and at chapter boundaries, and the context refresh
    /// on pause and interruption (#127, #160).
    private let siriSignals: PlayerSiriSignals
    /// Whether the user's last request was to play: set by `play`, cleared by `pause` and `unload`.
    /// By the time an interruption is posted the system has already paused the queue player, so
    /// its status can't say whether the interruption stopped playback; this can (#160).
    private var isPlayRequested = false
    /// Set while a multi-file book is loaded; `nil` for imported single-file books.
    private var multiFileQueue: MultiFileQueue?
    private var cancellables = Set<AnyCancellable>()
    private var hasSecurityAccess = false
    private let currentTimeSubject = PassthroughSubject<CMTime, Never>()
    private let playUrlSubject = PassthroughSubject<AudioModel, Never>()
    private var timeObserverToken: Any?
    /// A single-file book's seek target, until that seek completes (#151). While a book plays,
    /// `AVPlayer` keeps reporting the old time until a seek lands, so a second Next chapter
    /// pressed in between would aim at the same chapter. `MultiFileQueue` does the same for
    /// multi-file books with `pendingBookTime`.
    private var pendingSeek: PendingSeek?
    private var seekGeneration = 0

    /// The loaded book's identity (`AudioModel.url`), not where its file is: what callers compare
    /// rows, last played and speeds against (#186).
    var url: URL? {
        model?.url
    }

    var currentTimePublisher: AnyPublisher<CMTime, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    var playUrlSubjectPublisher: AnyPublisher<AudioModel, Never> {
        playUrlSubject.eraseToAnyPublisher()
    }

    /// KVO on `timeControlStatus` and `reasonForWaitingToPlay`, so a pause from anywhere (lock
    /// screen, CarPlay, an interruption) shows at once. Either change re-reads both on main, where
    /// they agree again, and maps them through `isPlaying(status:reason:)`.
    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        let status = player.publisher(for: \.timeControlStatus).map { _ in () }
        let reason = player.publisher(for: \.reasonForWaitingToPlay).map { _ in () }
        return status.merge(with: reason)
            .receive(on: DispatchQueue.main)
            .map { [player] in Self.isPlaying(status: player.timeControlStatus, reason: player.reasonForWaitingToPlay) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Book time. For a single file that is the item's time; a multi-file book adds the current
    /// chapter's start to the offset into its file. While a seek is in flight, it is where that
    /// seek is going (#151), so chapter skips, skips by seconds and saves aim from there.
    var currentTime: Double {
        if let multiFileQueue { return multiFileQueue.bookTime }
        if let pendingSeek, pendingSeek.item === player.currentItem { return pendingSeek.time }
        return player.currentTime().seconds
    }


    private(set) var playbackRate: Double = PlaybackSpeed.normal

    // MARK: - Init
    init(
        savePlaybackPositionUseCase: SavePlaybackPositionUseCaseProtocol = SavePlaybackPositionUseCase(),
        chapterResume: LoadChapterResumeUseCaseProtocol = LoadChapterResumeUseCase(),
        intentDonor: IntentDonorProtocol = IntentDonor.shared,
        librarySnapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared,
        audioSessionActivator: AudioSessionActivatorProtocol = AudioSessionActivator(),
        bookmarkProvider: BookmarkProviderProtocol = BookmarkProvider(),
        chapterPrioritizer: ChapterPrioritizing = NoopChapterPrioritizer(),
        downloadsRoot: URL = LibriVoxIdentity.defaultRoot,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        noticeReporter: NoticeReporting = NoticeCenter.shared,
        networkPath: NetworkPathProviding = NetworkPathMonitor.shared,
        speeds: PlaybackSpeedStoring = NormalPlaybackSpeed(),
        volumes: PlaybackVolumeStoring = FullPlaybackVolume(),
        lastPlayed: LastPlayedStore = .shared,
        launchState: LaunchStateFlag = .shared,
        siriContext: SiriContextRefreshing = NoopSiriContextRefresher()
    ) {
        self.speeds = speeds
        self.volumes = volumes
        self.lastPlayed = lastPlayed
        self.launchState = launchState
        self.siriSignals = PlayerSiriSignals(donor: intentDonor, context: siriContext)
        self.savePlaybackPositionUseCase = savePlaybackPositionUseCase
        self.chapterResume = chapterResume
        self.intentDonor = intentDonor
        self.librarySnapshotWriter = librarySnapshotWriter
        self.audioSessionActivator = audioSessionActivator
        self.bookmarkProvider = bookmarkProvider
        self.chapterPrioritizer = chapterPrioritizer
        self.downloadsRoot = downloadsRoot
        self.notificationCenter = notificationCenter
        self.now = now
        self.noticeReporter = noticeReporter
        self.networkPath = networkPath
        apply(volume: volumes.volume)
        setupTimeObserver()
        setupSaveObservers()

        // Initialize Now Playing and set player reference
        NowPlayingManager.shared.setPlayer(self, currentAudio: nil)
    }

    // MARK: - Deinit
    deinit {
        cleanup()
        notificationObservers.forEach(notificationCenter.removeObserver)
    }

    // MARK: - Cleanup
    func cleanup() {
        saveTime()
        stopAccessingCurrentURL()
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        NowPlayingManager.shared.clearNowPlaying()
    }

    func unload() {
        isPlayRequested = false
        player.pause()
        cancellables.removeAll()
        stopAccessingCurrentURL()
        multiFileQueue = nil
        player.removeAllItems()
        model = nil
        NowPlayingManager.shared.clearNowPlaying()
    }

    // MARK: - PlayerProtocol
    /// Every early return reports a `Notice` (#115), so a press that can't play says why.
    func play(_ model: inout AudioModel) {
        guard let url = model.url else {
            Log.player.error("play: the book has no URL")
            noticeReporter.report(.playbackFailed)
            return
        }

        // Step 1 — defense-in-depth audio session recovery
        do {
            try audioSessionActivator.activate()
            launchState.clear()
        } catch {
            launchState.markUnavailable()
            let error = error as NSError
            Log.player.error(
                "play: audio session activation failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)"
            )
            noticeReporter.report(.audioUnavailable)
            return
        }

        // Step 2 — lazy bookmark population on the inout model.
        // MUST happen BEFORE updatePlayItem so the playItem observer + any future Player
        // observer of the model see the populated bookmark via the copy.
        // A replay of the loaded book can come with a stale copy (a row built before the bookmark
        // existed): reuse the bookmark already held, rather than re-creating it and writing the
        // copy's old position over the one `pause` saved.
        if model.bookmarkData == nil, url == self.url, let loadedBookmark = self.model?.bookmarkData {
            model.bookmarkData = loadedBookmark
        }
        // `librivox://` identity URLs aren't files: there is nothing to bookmark.
        if !Self.isLibriVoxURL(url),
           model.bookmarkData == nil,
           let fileURL = model.fileURL,
           let bookmark = bookmarkProvider.createBookmarkData(for: fileURL) {
            model.bookmarkData = bookmark
            savePlaybackPositionUseCase.execute(
                url: model.url,
                currentTime: model.currentTime,
                bookmarkData: bookmark
            )
            librarySnapshotWriter.refresh()
        }

        Log.player.info("play: \(url.lastPathComponent, privacy: .private)")
        if url != self.url {
            saveTime()
            updatePlayItem(model)
            seek(model.currentTime)
        } else if hasFailedItem {
            // Play again after a failure retries with a fresh item, so a file put back (or a
            // connection back) plays, and a failure that persists is reported again.
            retryFailedItem(model)
        }
        // Sync the Now Playing gate on EVERY play, not only when the item changes.
        // `updatePlayItem` is skipped when the URL is unchanged, and `cleanup()` may have
        // dropped the gate in between -- so doing this only there leaves `currentAudio`
        // stale or nil while audio is actually playing.
        NowPlayingManager.shared.setPlayer(self, currentAudio: model)
        player.play()
        isPlayRequested = true
        Log.player.debug("play: started, timeControlStatus=\(self.player.timeControlStatus.rawValue, privacy: .public)")
        // The book's identity, which Siri loads it back by; never where its file is now (#186).
        lastPlayed.save(url: url)
        intentDonor.donatePlayMedia(model: model)
    }

    func pause() {
        isPlayRequested = false
        saveTime()
        player.pause()
        siriSignals.paused(model)
    }


    /// What the app shows as playing. Waiting counts only while the player buffers towards
    /// playback (the user's intent is play); waiting with no item to play (audio that can't load)
    /// or for any other reason is not playing, so the bar doesn't show "pause" forever.
    static func isPlaying(status: AVPlayer.TimeControlStatus, reason: AVPlayer.WaitingReason?) -> Bool {
        switch status {
        case .playing:
            return true
        case .waitingToPlayAtSpecifiedRate:
            return reason == .toMinimizeStalls || reason == .evaluatingBufferingRate
        case .paused:
            return false
        @unknown default:
            return false
        }
    }

    /// The same mapping as `isPlayingPublisher`, so `PlaybackCenter`'s seed at launch agrees with it.
    func isPlaying(_ url: URL?) -> Bool {
        guard let url = url, self.url == url else { return false }
        return Self.isPlaying(status: player.timeControlStatus, reason: player.reasonForWaitingToPlay)
    }

    // MARK: - Helpers
    private func updatePlayItem(_ item: AudioModel) {
        // Where the file is now: a moved book's differs from its identity, `item.url` (#186).
        guard let url = item.fileURL else {
            Log.player.error("updatePlayItem: the book has no URL")
            return
        }

        cancellables.removeAll()

        stopAccessingCurrentURL()
        multiFileQueue = nil

        if item.isLibriVox {
            loadMultiFileBook(item)
            return
        }

        hasSecurityAccess = url.startAccessingSecurityScopedResource()
        Log.player.debug(
            "updatePlayItem: security scope \(self.hasSecurityAccess, privacy: .public) for \(url.lastPathComponent, privacy: .private)"
        )
        model = item
        lastPositionSave = now()

        let playerItem = AVPlayerItem(url: url)
        boost.attach(to: playerItem)
        observeFailure(of: playerItem, book: item)
        // A single file's end is the book's: it pauses there by itself (`actionAtItemEnd`).
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.bookDidEnd() }
            .store(in: &cancellables)

        // A queue player advances (dropping the item) at its end by default; a single file must
        // stay put at the end the way the plain `AVPlayer` did, or the saved position resets.
        player.actionAtItemEnd = .pause
        player.removeAllItems()
        player.replaceCurrentItem(with: playerItem)
        applyBookSpeed(item.url)
        playUrlSubject.send(item)
    }

    /// Hands the book to a `MultiFileQueue`. No item is loaded here: `play` follows with
    /// `seek(model.currentTime)`, which loads the chapter that holds the saved position.
    private func loadMultiFileBook(_ item: AudioModel) {
        model = item
        lastPositionSave = now()
        player.removeAllItems()
        if let bookID = item.librivoxID {
            multiFileQueue = MultiFileQueue(
                player: player,
                chapters: item.chapters,
                bookID: bookID,
                downloadsRoot: downloadsRoot,
                prioritizer: chapterPrioritizer,
                onBookEnd: { [weak self] in
                    self?.pause()
                    self?.bookDidEnd()
                },
                onItemFailed: { [weak self] isStreaming in self?.chapterFailed(isStreaming: isStreaming) },
                prepareItem: { [boost] in boost.attach(to: $0) }
            )
        }
        applyBookSpeed(item.url)
        playUrlSubject.send(item)
    }

    private static func isLibriVoxURL(_ url: URL) -> Bool {
        url.scheme == LibriVoxIdentity.scheme
    }

    private func stopAccessingCurrentURL() {
        if hasSecurityAccess, let url = model?.fileURL {
            url.stopAccessingSecurityScopedResource()
            Log.player.debug("stopped accessing \(url.lastPathComponent, privacy: .private)")
            hasSecurityAccess = false
        }
    }

    /// Update-only (`SavePlaybackPositionUseCase`), so no caller can re-insert a deleted book.
    /// Writes the chapter it's in too, so that chapter can be resumed after a jump away (#299).
    private func saveTime() {
        let currentTime = self.currentTime
        if !currentTime.isNaN, let model = model {
            // Under the book's identity, not where its file is: a moved book's differ (#176).
            savePlaybackPositionUseCase.execute(
                url: model.url,
                currentTime: currentTime,
                bookmarkData: nil,
                chapter: model.chapterPosition(at: currentTime)
            )
            lastPositionSave = now()
        }
    }

    // MARK: - Setups
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] itemTime in
            // The observer reports the item's time; for a multi-file book publish book time.
            let time = self?.multiFileQueue.map { CMTime(seconds: $0.bookTime, preferredTimescale: 600) } ?? itemTime
            self?.currentTimeSubject.send(time)

            // Update Now Playing with current time
            guard let self = self, let model = self.model else { return }
            let currentTime = time.seconds
            let isPlaying = self.player.timeControlStatus == .playing

            NowPlayingManager.shared.updateNowPlaying(
                for: model,
                currentTime: currentTime,
                isPlaying: isPlaying,
                playbackRate: self.playbackRate
            )
            self.savePositionIfDue(isPlaying: isPlaying)
            self.noteChapter(atBookTime: currentTime, isPlaying: isPlaying)
        }
    }
}

// MARK: - Seeking
/// A single-file seek in flight: where it goes, the item it was asked of (once the player has moved
/// off that item the target is stale) and which seek it was.
private struct PendingSeek {
    let time: Double
    let item: AVPlayerItem?
    let generation: Int
}

extension Player {
    func seek(_ seconds: Double) {
        // A jump, not playback: a chapter left this way isn't finished (#299).
        chapterCompletion.jumped()
        if let multiFileQueue {
            multiFileQueue.seek(toBookTime: seconds)
            return
        }
        seekSingleFile(to: seconds)
    }

    private func seekSingleFile(to seconds: Double) {
        guard seconds.isFinite else { return }
        // Exact and rounded up, never before the target: chapter lookup has no lead-in (#101), so
        // landing even a millisecond before a chapter's start would read as the previous chapter,
        // and the next skip would aim at the same chapter again.
        let time = CMTime(value: CMTimeValue((seconds * 600).rounded(.up)), timescale: 600)
        seekGeneration += 1
        let generation = seekGeneration
        pendingSeek = PendingSeek(time: time.seconds, item: player.currentItem, generation: generation)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                // Only the latest seek clears it, finished or not (as in `MultiFileQueue`, #130):
                // an earlier one completing must not expose the old time in between.
                guard let self, self.pendingSeek?.generation == generation else { return }
                self.pendingSeek = nil
            }
        }
    }
}

// MARK: - Chapter boundaries: Siri donations and finished chapters
extension Player {
    /// Called on every periodic-observer tick, to donate when playback crosses into another
    /// chapter (#127). Internal for tests: the observer only fires while an item plays.
    func noteChapter(atBookTime time: Double, isPlaying: Bool) {
        siriSignals.tick(model, bookTime: time, isPlaying: isPlaying)
        // A chapter played into the next one is finished: saved as its full length (#299).
        for index in chapterCompletion.tick(model, bookTime: time, isPlaying: isPlaying) {
            guard let model, model.chapters.indices.contains(index) else { continue }
            savePlaybackPositionUseCase.execute(
                url: model.url,
                currentTime: time,
                bookmarkData: nil,
                chapter: ChapterPosition(index: index, offset: model.chapters[index].duration)
            )
        }
    }
}

// MARK: - Saving the position while playing
extension Player {
    /// How often a playing book's position is written (#117). Pausing, switching books and
    /// jumping to a chapter save at once; this bounds what a crash, jetsam or power loss can lose.
    static let positionSaveInterval: TimeInterval = 10

    /// The book played to its end (#299). Its last chapter has no next chapter to play into, so
    /// `ChapterCompletion` never sees it finish, and the last save while playing can be seconds
    /// before the end (a LibriVox file can also be shorter than its listed duration): it is saved
    /// at its full length here, so a tap on it starts it over. Internal for tests.
    func bookDidEnd() {
        guard let model, let last = model.chapters.indices.last else {
            saveTime()
            return
        }
        savePlaybackPositionUseCase.execute(
            url: model.url,
            currentTime: currentTime,
            bookmarkData: nil,
            chapter: ChapterPosition(index: last, offset: model.chapters[last].duration)
        )
        lastPositionSave = now()
    }

    /// Called on every periodic-observer tick. Saves while playing, at most once per
    /// `positionSaveInterval`. Internal for tests: the observer only fires while an item plays.
    func savePositionIfDue(isPlaying: Bool) {
        guard isPlaying else { return }
        if let lastPositionSave, now().timeIntervalSince(lastPositionSave) < Self.positionSaveInterval { return }
        saveTime()
    }

    /// Saves when the app may not get another chance (#117): an interruption (a call, Siri,
    /// another app's audio) can stop playback without `pause()`, and a backgrounded app can be
    /// killed by the system without `applicationWillTerminate`. An interruption that stopped
    /// playback also sends Siri the signals a pause would (#160).
    private func setupSaveObservers() {
        let interruption = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began
            else { return }
            guard let self else { return }
            saveTime()
            siriSignals.interrupted(model, wasPlaying: isPlayRequested)
        }
        let background = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveTime()
        }
        notificationObservers = [interruption, background]
    }
}

// MARK: - Failures
extension Player {
    /// The loaded book's item failed. A queue player drops a failed item, so a single file with no
    /// item left has failed too.
    private var hasFailedItem: Bool {
        if let multiFileQueue { return multiFileQueue.currentItemFailed }
        return player.currentItem.map { $0.status == .failed } ?? true
    }

    /// No `saveTime()`: a failed item has no position worth keeping.
    private func retryFailedItem(_ model: AudioModel) {
        Log.player.info("play: retrying a failed item")
        if let multiFileQueue {
            multiFileQueue.reload(atBookTime: currentTime)
        } else {
            updatePlayItem(model)
            seek(model.currentTime)
        }
    }

    /// An imported file's item failed to load, or failed mid-play. Stored in `cancellables`, so it
    /// goes with the item.
    private func observeFailure(of playerItem: AVPlayerItem, book: AudioModel) {
        playerItem.publisher(for: \.status)
            .filter { $0 == .failed }
            .sink { [weak self, weak playerItem] _ in
                self?.fileFailed(book, error: playerItem?.error)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
            .sink { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self?.fileFailed(book, error: error)
            }
            .store(in: &cancellables)
    }

    /// A file that is no longer there was moved, renamed or deleted, so its bookmark can't find it:
    /// importing it again fixes that. A file that is there but won't play can't be fixed that way.
    private func fileFailed(_ book: AudioModel, error: Error?) {
        let error = error as NSError?
        let isReachable = (try? book.fileURL?.checkResourceIsReachable()) == true
        Log.player.error(
            """
            item failed: \(book.fileURL?.lastPathComponent ?? "", privacy: .private), \
            reachable=\(isReachable, privacy: .public), \
            \(error?.domain ?? "", privacy: .public) \(error?.code ?? 0, privacy: .public)
            """
        )
        stopAfterFailure()
        noticeReporter.report(isReachable ? .playbackFailed : .fileMissing(title: Notice.title(of: book)))
    }

    /// The LibriVox chapter being played failed. Streaming one while offline is the common case
    /// (#130): Play on a chapter that isn't downloaded, without a connection.
    private func chapterFailed(isStreaming: Bool) {
        let isOnline = networkPath.isOnline
        Log.player.error(
            "chapter failed: streaming=\(isStreaming, privacy: .public), online=\(isOnline, privacy: .public)"
        )
        stopAfterFailure()
        noticeReporter.report(isStreaming && !isOnline ? .streamingOffline : .chapterFailed)
    }

    /// A player asked to play keeps its rate after its item fails, and with no item left it can
    /// report itself as playing, so the bar and the row showed Pause and the first tap only paused
    /// (#115). Pausing makes them show Play, and one tap retries through `play`. No `saveTime()`:
    /// a failed item has no position worth keeping.
    private func stopAfterFailure() {
        player.pause()
    }
}

// MARK: - For tests
extension Player {
    internal var currentItemURL: URL? { (player.currentItem?.asset as? AVURLAsset)?.url }

    /// What the queue player was asked for, for tests: `rate` is 0 while paused, `defaultRate` is
    /// what the next `play()` starts at.
    internal var requestedRates: (rate: Float, defaultRate: Float) { (player.rate, player.defaultRate) }

    /// The queue player's own gain, for tests.
    internal var requestedVolume: Float { player.volume }
    /// The boost's gain past 100%, for tests.
    internal var boostGain: Double { boost.gain }
}

// MARK: - Speed
extension Player {
    func setPlaybackRate(_ rate: Double) {
        let speed = PlaybackSpeed.snap(rate)
        if let url = model?.url {
            speeds.setSpeed(speed, for: url)
        }
        apply(speed: speed)
        if let model {
            NowPlayingManager.shared.updateNowPlaying(
                for: model,
                currentTime: currentTime,
                isPlaying: player.timeControlStatus == .playing,
                playbackRate: speed
            )
        }
    }

    /// A book plays at its own speed. The first time it loads it has none, so it takes the default
    /// for new books and keeps it: changing the default later changes only books not played yet.
    private func applyBookSpeed(_ url: URL?) {
        let speed = speeds.playbackSpeed(for: url)
        speeds.setSpeed(speed, for: url)
        apply(speed: speed)
    }

    /// One `AVQueuePlayer` plays every chapter file, so its `defaultRate` (what `play()` starts at)
    /// carries the speed across pause and resume, seeks and file hand-offs. A playing player also
    /// takes the new `rate` at once.
    private func apply(speed: Double) {
        playbackRate = speed
        player.defaultRate = Float(speed)
        if player.rate != 0 {
            player.rate = Float(speed)
        }
    }
}

// MARK: - Volume
extension Player {
    var volume: Double { volumes.volume }

    /// One `AVQueuePlayer` plays every book and chapter file, so its `volume` holds across them.
    /// It is the player's gain, not the system volume: other apps (a call) stay as loud as they were.
    func setVolume(_ volume: Double) {
        let level = BookVolume.snap(volume)
        volumes.volume = level
        apply(volume: level)
    }

    /// Up to 100% the queue player's `volume`; past it the player stays at full and the boost
    /// carries the rest.
    private func apply(volume: Double) {
        player.volume = Float(BookVolume.playerVolume(volume))
        boost.gain = BookVolume.boostGain(volume)
    }
}

// MARK: - Relative skips
extension Player {
    func forward(withSeconds seconds: Double) {
        let currentSeconds = currentTime
        let newSeconds = currentSeconds.advanced(by: seconds)
        seek(newSeconds)
    }

    func backward(withSeconds seconds: Double) {
        let currentSeconds = currentTime
        let newSeconds = currentSeconds.advanced(by: -seconds)
        seek(newSeconds)
    }
}

// MARK: - Chapter navigation
extension Player {
    func skipToNextChapter() {
        guard let model, let currentChapterIndex = model.currentChapter(for: currentTime) else { return }
        let nextChapterIndex = currentChapterIndex + 1
        guard nextChapterIndex < model.chapters.count else { return }
        saveTime()
        seek(model.chapters[nextChapterIndex].startTime)
    }

    func skipToPreviousChapter() {
        guard let model = model else { return }
        // A book with no chapter metadata -- a plain MP3, the common case rather than an edge
        // case (#102) -- has no current chapter: go to the start. Reachable from
        // PreviousChapterIntent and from the lock-screen / CarPlay previous-track handler.
        guard let currentChapterIndex = model.currentChapter(for: currentTime),
              model.chapters.indices.contains(currentChapterIndex) else {
            seek(0)
            return
        }
        let currentChapter = model.chapters[currentChapterIndex]
        saveTime()

        // If more than 15 seconds into the chapter, go to start of current chapter
        // Otherwise, go to previous chapter
        if currentTime - currentChapter.startTime > 15 {
            seek(currentChapter.startTime)
        } else if currentChapterIndex > 0 {
            seek(model.chapters[currentChapterIndex - 1].startTime)
        } else {
            seek(0)
        }
    }

    /// Jumps the loaded book to a chapter, where it was left (#299), and resumes playback. The
    /// chapter already playing isn't moved (its saved offset trails the playhead by up to
    /// `positionSaveInterval`), unless it was listened to its end: then it starts over. Next and
    /// previous chapter still go to a chapter's start.
    /// Returns `false` when no book is loaded or the index is out of range, so
    /// callers (Siri's "play chapter N") can speak the right failure instead of
    /// silently doing nothing.
    @discardableResult
    func playChapter(at index: Int) -> Bool {
        guard let model = model, model.chapters.indices.contains(index) else { return false }
        let chapter = model.chapters[index]
        if model.currentChapter(for: currentTime) != index {
            // Read first: saving writes the chapter being left, never this one.
            let target = resumeTime(ofChapter: index, in: model)
            saveTime()
            seek(target)
        } else if chapter.isFinished(at: currentTime) {
            saveTime()
            seek(chapter.startTime)
        }
        player.play()
        return true
    }

    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double {
        guard book.chapters.indices.contains(index) else { return 0 }
        return chapterResume.resumeTime(ofChapter: index, in: book) ?? book.chapters[index].resumeTime
    }

    /// Next and previous chapter, chapter taps, Siri and the lock screen read the chapters from
    /// `model`, so they follow at once. A LibriVox book's chapters are its files: never replaced.
    func replaceChapters(_ chapters: [ChapterModel], ofBookAt url: URL) {
        guard var model, model.url == url, multiFileQueue == nil else { return }
        model.chapters = chapters
        self.model = model
        if NowPlayingManager.shared.currentAudio?.url == url {
            NowPlayingManager.shared.setPlayer(self, currentAudio: model)
        }
    }
}

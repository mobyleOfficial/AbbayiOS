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
    @discardableResult
    func playChapter(at index: Int) -> Bool
    /// The loaded book's speed; normal speed when nothing is loaded.
    var playbackRate: Double { get }
    /// Sets the loaded book's speed, saves it for that book, and applies it at once when playing.
    /// It holds across pause and resume, seeks and chapter files.
    func setPlaybackRate(_ rate: Double)
}

/// For players with no speed control (test doubles that predate it).
extension PlayerProtocol {
    var playbackRate: Double { PlaybackSpeed.normal }

    func setPlaybackRate(_ rate: Double) {}
}

final class Player: PlayerProtocol {
    // MARK: - Properties
    // A queue player for every book: single-file books only ever hold one item, multi-file
    // (LibriVox) books hold the current chapter's file plus the next one for gapless playback.
    private let player = AVQueuePlayer()
    private var model: AudioModel?
    /// Update-only: a book deleted while it's loaded here must not be re-inserted.
    private let savePlaybackPositionUseCase: SavePlaybackPositionUseCaseProtocol
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
    /// chapter's start to the offset into its file.
    var currentTime: Double {
        multiFileQueue?.bookTime ?? player.currentTime().seconds
    }

    internal var currentItemURL: URL? { (player.currentItem?.asset as? AVURLAsset)?.url }

    /// What the queue player was asked for, for tests: `rate` is 0 while paused, `defaultRate` is
    /// what the next `play()` starts at.
    internal var requestedRates: (rate: Float, defaultRate: Float) { (player.rate, player.defaultRate) }

    private(set) var playbackRate: Double = PlaybackSpeed.normal

    // MARK: - Init
    init(
        savePlaybackPositionUseCase: SavePlaybackPositionUseCaseProtocol = SavePlaybackPositionUseCase(),
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
        lastPlayed: LastPlayedStore = .shared,
        launchState: LaunchStateFlag = .shared,
        siriContext: SiriContextRefreshing = NoopSiriContextRefresher()
    ) {
        self.speeds = speeds
        self.lastPlayed = lastPlayed
        self.launchState = launchState
        self.siriSignals = PlayerSiriSignals(donor: intentDonor, context: siriContext)
        self.savePlaybackPositionUseCase = savePlaybackPositionUseCase
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
           let bookmark = bookmarkProvider.createBookmarkData(for: url) {
            model.bookmarkData = bookmark
            savePlaybackPositionUseCase.execute(url: url, currentTime: model.currentTime, bookmarkData: bookmark)
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

    func seek(_ seconds: Double) {
        if let multiFileQueue {
            multiFileQueue.seek(toBookTime: seconds)
            return
        }
        guard seconds.isFinite else { return }
        // Exact and rounded up, never before the target: chapter lookup has no lead-in (#101), so
        // landing even a millisecond before a chapter's start would read as the previous chapter,
        // and the next skip would aim at the same chapter again.
        let time = CMTime(value: CMTimeValue((seconds * 600).rounded(.up)), timescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skipToNextChapter() {
        guard let model, let currentChapterIndex = model.currentChapter(for: currentTime) else { return }
        let nextChapterIndex = currentChapterIndex + 1
        guard nextChapterIndex < model.chapters.count else { return }
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

    /// Jumps the loaded book to the start of a chapter and resumes playback.
    /// Returns `false` when no book is loaded or the index is out of range, so
    /// callers (Siri's "play chapter N") can speak the right failure instead of
    /// silently doing nothing.
    @discardableResult
    func playChapter(at index: Int) -> Bool {
        guard let model = model, model.chapters.indices.contains(index) else { return false }
        saveTime()
        seek(model.chapters[index].startTime)
        player.play()
        return true
    }

    // MARK: - Helpers
    private func updatePlayItem(_ item: AudioModel) {
        guard let url = item.url else {
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
        observeFailure(of: playerItem, book: item)

        // A queue player advances (dropping the item) at its end by default; a single file must
        // stay put at the end the way the plain `AVPlayer` did, or the saved position resets.
        player.actionAtItemEnd = .pause
        player.removeAllItems()
        player.replaceCurrentItem(with: playerItem)
        applyBookSpeed(url)
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
                onBookEnd: { [weak self] in self?.pause() },
                onItemFailed: { [weak self] isStreaming in self?.chapterFailed(isStreaming: isStreaming) }
            )
        }
        applyBookSpeed(item.url)
        playUrlSubject.send(item)
    }

    private static func isLibriVoxURL(_ url: URL) -> Bool {
        url.scheme == LibriVoxIdentity.scheme
    }

    private func stopAccessingCurrentURL() {
        if hasSecurityAccess, let url = url {
            url.stopAccessingSecurityScopedResource()
            Log.player.debug("stopped accessing \(url.lastPathComponent, privacy: .private)")
            hasSecurityAccess = false
        }
    }

    /// Update-only (`SavePlaybackPositionUseCase`), so no caller can re-insert a deleted book.
    private func saveTime() {
        let currentTime = self.currentTime
        if !currentTime.isNaN, let model = model {
            savePlaybackPositionUseCase.execute(url: model.url, currentTime: currentTime, bookmarkData: nil)
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

// MARK: - Siri donations at chapter boundaries
extension Player {
    /// Called on every periodic-observer tick, to donate when playback crosses into another
    /// chapter (#127). Internal for tests: the observer only fires while an item plays.
    func noteChapter(atBookTime time: Double, isPlaying: Bool) {
        siriSignals.tick(model, bookTime: time, isPlaying: isPlaying)
    }
}

// MARK: - Saving the position while playing
extension Player {
    /// How often a playing book's position is written (#117). Pausing, switching books and
    /// jumping to a chapter save at once; this bounds what a crash, jetsam or power loss can lose.
    static let positionSaveInterval: TimeInterval = 10

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
        let isReachable = (try? book.url?.checkResourceIsReachable()) == true
        Log.player.error(
            """
            item failed: \(book.url?.lastPathComponent ?? "", privacy: .private), \
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

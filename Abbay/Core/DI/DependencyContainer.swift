//
//  DependencyContainer.swift
//  Abbay
//

import Foundation

protocol DependencyContainerProtocol {
    var player: PlayerProtocol { get }
    var loadAudio: LoadAudioUseCaseProtocol { get }
    var loadAllAudios: LoadAllAudiosUseCaseProtocol { get }
    var downloads: BookDownloadManagerProtocol { get }
    /// The one app-wide playback source; views read its state and clock instead of the player.
    var playback: PlaybackCenter { get }
    /// The one app-wide download source, one observable entry per book.
    var downloadStates: DownloadStateStore { get }
    /// The app's settings: skip intervals, speeds, downloads and language.
    var settings: AppSettings { get }
    /// The App Group values Siri shares with the extension. Here so the code the system builds
    /// itself (App Intents, entity queries) gets them injected like everything else.
    var lastPlayed: LastPlayedStore { get }
    var launchState: LaunchStateFlag { get }
    var librarySnapshot: LibrarySnapshotReader { get }
    /// Re-publishes the library to Siri on foreground, pause and the daily background task (#127).
    var siriContext: SiriContextRefreshing { get }
    /// The Siri diagnostics trail (the App Group's) the App Intents and entity queries record to.
    var diagnostics: SiriDiagnostics { get }
    /// What App Intents activate the audio session with before they play (#153: was a static).
    var audioSessionActivator: AudioSessionActivatorProtocol { get }
    /// Read-along's engine, store and settings (#192); unavailable below iOS 26.
    var readAlong: ReadAlongCenter { get }
}

final class DependencyContainer: DependencyContainerProtocol {
    private static var _shared: DependencyContainerProtocol?

    static var shared: DependencyContainerProtocol {
        guard let container = _shared else {
            fatalError("DependencyContainer not configured. Call configure() in AppDelegate.")
        }
        return container
    }

    /// True once `configure()` has run. AppIntents entity queries can be evaluated
    /// before/without the normal launch path, and `shared` traps when unconfigured,
    /// so those call sites check this and fall back to the App Group snapshot.
    static var isConfigured: Bool {
        _shared != nil
    }

    static func configure(with container: DependencyContainerProtocol? = nil) {
        _shared = container ?? DependencyContainer()
    }

    static func reset() {
        _shared = nil
    }

    let player: PlayerProtocol
    let loadAudio: LoadAudioUseCaseProtocol
    let loadAllAudios: LoadAllAudiosUseCaseProtocol
    let downloads: BookDownloadManagerProtocol
    let playback: PlaybackCenter
    let downloadStates: DownloadStateStore
    let settings: AppSettings
    let lastPlayed: LastPlayedStore = .shared
    let launchState: LaunchStateFlag = .shared
    let librarySnapshot: LibrarySnapshotReader = .shared
    let siriContext: SiriContextRefreshing
    let diagnostics: SiriDiagnostics = .shared
    let audioSessionActivator: AudioSessionActivatorProtocol = AudioSessionActivator()
    let readAlong: ReadAlongCenter

    private init() {
        // `shared`, not a new instance: `configure()` can run more than once per process, and a
        // background session identifier may back only one session.
        let downloads = Self.makeDownloads()
        self.downloads = downloads
        // Before the player: it reads each book's speed from here as it loads it.
        let settings = AppSettings(
            store: DebugOverrides.settingsStore() ?? LocalStorage.preferences,
            effects: LiveSettingsEffects()
        )
        self.settings = settings
        let loadAllAudios = LoadAllAudiosUseCase()
        self.loadAllAudios = loadAllAudios
        // Before the player: a pause refreshes Siri's context through it.
        let siriContext = SiriContextRefresher(loadAllAudios: loadAllAudios)
        self.siriContext = siriContext
        let player = Player(chapterPrioritizer: downloads, speeds: settings, siriContext: siriContext)
        let loadAudio = LoadAudioUseCase()
        self.player = player
        self.loadAudio = loadAudio
        // Built here, on main: `configure()` runs from the AppDelegate's launch.
        self.playback = PlaybackCenter(player: player, loadAudio: loadAudio)
        self.downloadStates = DownloadStateStore(downloads: downloads, path: NetworkPathMonitor.app)
        // Sessions stop themselves when Read-along is turned off, which deletes every transcript.
        // `.shared` is also the store the off switch and book deletion use (a temporary one under
        // `-seedReadAlong`).
        self.readAlong = ReadAlongCenter(
            transcriber: Self.makeReadAlongTranscriber(),
            store: .shared,
            settings: settings
        )
    }

    /// The App Group stores for code that can run before launch configured the container (entity
    /// queries): the container's once it is configured, else the App Group's own.
    static var lastPlayed: LastPlayedStore {
        isConfigured ? shared.lastPlayed : .shared
    }

    static var launchState: LaunchStateFlag {
        isConfigured ? shared.launchState : .shared
    }

    static var librarySnapshot: LibrarySnapshotReader {
        isConfigured ? shared.librarySnapshot : .shared
    }

    static var diagnostics: SiriDiagnostics {
        isConfigured ? shared.diagnostics : .shared
    }

    static var audioSessionActivator: AudioSessionActivatorProtocol {
        isConfigured ? shared.audioSessionActivator : AudioSessionActivator()
    }

    private static func makeDownloads() -> BookDownloadManagerProtocol {
        DebugOverrides.downloadManager() ?? BookDownloadManager.shared
    }

    /// The canned stub under `-seedReadAlong`, else the speech engine where iOS has it.
    private static func makeReadAlongTranscriber() -> ReadAlongTranscribing? {
        if let stub = DebugOverrides.readAlongTranscriber() {
            return stub
        }
        if #available(iOS 26, *) {
            return SpeechReadAlongTranscriber()
        }
        return nil
    }
}

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

    private init() {
        // `shared`, not a new instance: `configure()` can run more than once per process, and a
        // background session identifier may back only one session.
        let downloads = Self.makeDownloads()
        self.downloads = downloads
        let player = Player(chapterPrioritizer: downloads)
        let loadAudio = LoadAudioUseCase()
        self.player = player
        self.loadAudio = loadAudio
        // Built here, on main: `configure()` runs from the AppDelegate's launch.
        self.playback = PlaybackCenter(player: player, loadAudio: loadAudio)
        self.downloadStates = DownloadStateStore(downloads: downloads)
        self.loadAllAudios = LoadAllAudiosUseCase()
    }

    private static func makeDownloads() -> BookDownloadManagerProtocol {
        DebugOverrides.downloadManager() ?? BookDownloadManager.shared
    }
}

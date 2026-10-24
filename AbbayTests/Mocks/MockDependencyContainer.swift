//
//  MockDependencyContainer.swift
//  AbbayTests
//

@testable import Abbay

final class MockDependencyContainer: DependencyContainerProtocol {
    let player: PlayerProtocol
    let loadAudio: LoadAudioUseCaseProtocol
    let loadAllAudios: LoadAllAudiosUseCaseProtocol
    let downloads: BookDownloadManagerProtocol
    let playback: PlaybackCenter
    let downloadStates: DownloadStateStore
    let settings: AppSettings
    let lastPlayed: LastPlayedStore
    let launchState: LaunchStateFlag
    let librarySnapshot: LibrarySnapshotReader
    let siriContext: SiriContextRefreshing = NoopSiriContextRefresher()
    let diagnostics: SiriDiagnostics
    var audioSessionActivator: AudioSessionActivatorProtocol

    /// The App Group stores default to one fresh in-memory store, so nothing a test does through
    /// the container reaches the real App Group. Pass `appGroup` to seed or inspect it.
    init(player: PlayerProtocol,
         loadAudio: LoadAudioUseCaseProtocol,
         loadAllAudios: LoadAllAudiosUseCaseProtocol,
         downloads: BookDownloadManagerProtocol = MockBookDownloadManager(),
         settings: AppSettings = AppSettings(store: InMemoryKeyValueStore()),
         appGroup: KeyValueStoring = InMemoryKeyValueStore(),
         audioSessionActivator: AudioSessionActivatorProtocol = MockAudioSessionActivator()) {
        self.settings = settings
        self.lastPlayed = LastPlayedStore(store: appGroup, legacyStore: InMemoryKeyValueStore())
        self.launchState = LaunchStateFlag(store: appGroup)
        self.librarySnapshot = LibrarySnapshotReader(store: appGroup)
        self.diagnostics = SiriDiagnostics(store: appGroup)
        self.audioSessionActivator = audioSessionActivator
        self.player = player
        self.loadAudio = loadAudio
        self.loadAllAudios = loadAllAudios
        self.downloads = downloads
        self.downloadStates = DownloadStateStore(downloads: downloads)
        self.playback = PlaybackCenter(player: player, loadAudio: loadAudio)
    }
}

/// A publisher that does nothing: for real `LibrarySnapshotWriter`s in tests, so a snapshot write
/// never reaches the real Siri vocabulary, Spotlight index or diagnostics trail (#153).
struct NoopSiriLibraryPublisher: SiriLibraryPublisherProtocol {
    func publish(audios: [AudioModel], completion: @escaping () -> Void) {
        completion()
    }
}

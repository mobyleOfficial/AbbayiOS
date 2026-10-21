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

    private init() {
        // `shared`, not a new instance: `configure()` can run more than once per process, and a
        // background session identifier may back only one session.
        let downloads = Self.makeDownloads()
        self.downloads = downloads
        self.player = Player(chapterPrioritizer: downloads)
        self.loadAudio = LoadAudioUseCase()
        self.loadAllAudios = LoadAllAudiosUseCase()
    }

    private static func makeDownloads() -> BookDownloadManagerProtocol {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(LaunchArgument.stubLibriVox) {
            return UITestDownloadManager()
        }
        #endif
        return BookDownloadManager.shared
    }
}

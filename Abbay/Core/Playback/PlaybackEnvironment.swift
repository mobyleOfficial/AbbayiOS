//
//  PlaybackEnvironment.swift
//  Abbay
//

import SwiftUI

private struct PlaybackCenterKey: EnvironmentKey {
    static let defaultValue: PlaybackCenter? = nil
}

private struct DownloadStateStoreKey: EnvironmentKey {
    static let defaultValue: DownloadStateStore? = nil
}

extension EnvironmentValues {
    /// Where row actions go (`player`). Optional so previews can omit it: actions then do nothing.
    var playbackCenter: PlaybackCenter? {
        get { self[PlaybackCenterKey.self] }
        set { self[PlaybackCenterKey.self] = newValue }
    }

    /// The per-book download entries. Optional for the same reason; rows then show no ring.
    var downloadStateStore: DownloadStateStore? {
        get { self[DownloadStateStoreKey.self] }
        set { self[DownloadStateStoreKey.self] = newValue }
    }
}

extension View {
    /// Injects the app-wide playback and download sources. `PlaybackState` and `PlaybackClock` go
    /// in as observable objects, so a view depends only on the properties it actually reads.
    @MainActor
    func playbackEnvironment(_ container: DependencyContainerProtocol) -> some View {
        environment(container.playback.state)
            .environment(container.playback.clock)
            .environment(\.playbackCenter, container.playback)
            .environment(\.downloadStateStore, container.downloadStates)
    }
}

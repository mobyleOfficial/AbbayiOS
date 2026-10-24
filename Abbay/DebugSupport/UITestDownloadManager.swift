//
//  UITestDownloadManager.swift
//  Abbay
//

#if DEBUG
import Combine
import Foundation

/// Downloads nothing, so UI tests never create the background session or reach the network.
/// Enabled by `LaunchArgument.stubLibriVox`.
final class UITestDownloadManager: BookDownloadManagerProtocol {
    var statesPublisher: AnyPublisher<[String: BookDownloadState], Never> {
        Just([:]).eraseToAnyPublisher()
    }

    func enqueue(_ book: AudioModel) {}
    func pause(bookID: String) {}
    func resume(bookID: String) {}
    func remove(bookID: String) {}
    func restore() {}
    func handleBackgroundEvents(completion: @escaping () -> Void) { completion() }
    func prioritize(chapterIndex: Int, ofBookID id: String) {}
    func retry(chapterIndex: Int, ofBookID id: String) {}
}
#endif

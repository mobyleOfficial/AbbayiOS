//
//  UITestDownloadManager.swift
//  Abbay
//

#if DEBUG
import Combine
import Foundation

/// Downloads nothing, so UI tests never create the background session or reach the network.
/// Enabled by `LaunchArgument.stubLibriVox`.
///
/// With `publishesStates` (`LaunchArgument.stubDownloadStates`) every enqueued book gets a state
/// that never moves on its own: its first chapter downloaded, its last one failed and the rest
/// waiting, so the progress bar, the ring, a waiting chapter and a retry button can all be reached.
/// Pause, resume and retry change that state the way the real manager would.
final class UITestDownloadManager: BookDownloadManagerProtocol {
    private let publishesStates: Bool
    private let states = CurrentValueSubject<[String: BookDownloadState], Never>([:])

    init(publishesStates: Bool = false) {
        self.publishesStates = publishesStates
    }

    var statesPublisher: AnyPublisher<[String: BookDownloadState], Never> {
        states.eraseToAnyPublisher()
    }

    func enqueue(_ book: AudioModel) {
        guard publishesStates, let id = book.librivoxID else { return }
        states.value[id] = Self.initialState(chapterCount: max(book.chapters.count, 1))
    }

    func pause(bookID: String) {
        states.value[bookID]?.isPaused = true
    }

    func resume(bookID: String) {
        states.value[bookID]?.isPaused = false
    }

    func remove(bookID: String) {
        states.value[bookID] = nil
    }

    func restore() {}
    func handleBackgroundEvents(completion: @escaping () -> Void) { completion() }
    func prioritize(chapterIndex: Int, ofBookID id: String) {}

    func retry(chapterIndex: Int, ofBookID id: String) {
        guard var state = states.value[id], state.chapters.indices.contains(chapterIndex) else { return }
        state.chapters[chapterIndex] = .waiting
        states.value[id] = state
    }

    /// The first chapter done, the last failed, any others waiting; equal sizes.
    static func initialState(chapterCount: Int) -> BookDownloadState {
        var chapters = [ChapterDownloadState](repeating: .waiting, count: chapterCount)
        chapters[0] = .downloaded
        if chapterCount > 1 { chapters[chapterCount - 1] = .failed }
        return BookDownloadState(
            chapters: chapters,
            expectedBytes: [Int64](repeating: 1, count: chapterCount),
            isPaused: false
        )
    }
}
#endif

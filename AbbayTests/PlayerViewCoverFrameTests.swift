@testable import Abbay
import SwiftUI
import XCTest

/// The player reports its cover's frame so the expansion's growing cover can land on it (#244).
/// The reported frame must be the square that is drawn: when the height runs short, the frame
/// around it is wider, and a cover landing there snapped down as the player settled (#254).
@MainActor
final class PlayerViewCoverFrameTests: XCTestCase {
    func test_reportedCoverFrame_isTheDrawnSquare_onShortAndTallScreens() throws {
        // iPhone SE, iPhone 15 and iPhone 17 Pro Max, in points.
        let sizes = [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852), CGSize(width: 440, height: 956)]
        for size in sizes {
            let frame = try XCTUnwrap(reportedCoverFrame(in: size), "no cover frame at \(size)")
            XCTAssertEqual(frame.width, frame.height, accuracy: 0.5, "not square at \(size): \(frame)")
            XCTAssertLessThanOrEqual(frame.width, PlayerView.coverSide + 0.5, "wider than coverSide at \(size)")
            XCTAssertGreaterThan(frame.width, 0)
        }
    }

    private func reportedCoverFrame(in size: CGSize) -> CGRect? {
        var reported: CGRect?
        let book = AudioModel(
            title: "Pride and Prejudice",
            albumName: "",
            artist: "Jane Austen",
            duration: 48_657,
            chapters: [ChapterModel](repeating: ChapterModel(title: "Chapter"), count: 3)
        )
        let view = PlayerView(
            model: PlayerViewModel(book, state: PlaybackState(), player: nil, downloads: nil),
            onCoverFrame: { reported = $0 }
        )
        .environment(PlaybackClock())
        .environment(AppSettings(store: InMemoryKeyValueStore()))
        .coordinateSpace(.named(PlayerView.coordinateSpace))
        .frame(width: size.width, height: size.height)

        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.isHidden = true
        return reported
    }
}

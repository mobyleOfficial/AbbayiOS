//
//  ReadAlongControlsVisibilityTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The read-along controls' auto-hide (#192, owner's follow-up): visible, then hidden after a
/// delay with no interaction; any interaction brings them back and starts the delay again; never
/// hidden while VoiceOver runs, the language menu is open, the text isn't ready or something
/// covers the controls.
@MainActor
final class ReadAlongControlsVisibilityTests: XCTestCase {
    /// Runs scheduled hides when the test says so, not on a clock.
    private final class ManualScheduler {
        private var pending: [Int: () -> Void] = [:]
        private var next = 0
        private(set) var delays: [Duration] = []

        var pendingCount: Int { pending.count }

        func schedule(_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> () -> Void {
            let id = next
            next += 1
            delays.append(delay)
            pending[id] = action
            return { [weak self] in self?.pending[id] = nil }
        }

        /// The delay passes for everything scheduled.
        func elapse() {
            let actions = pending.values
            pending = [:]
            actions.forEach { $0() }
        }
    }

    private func makeSUT(delay: Duration = .seconds(3)) -> (ReadAlongControlsVisibility, ManualScheduler) {
        let scheduler = ManualScheduler()
        let sut = ReadAlongControlsVisibility(delay: delay) { delay, action in
            scheduler.schedule(delay, action)
        }
        return (sut, scheduler)
    }

    func test_startsVisible_andHidesOnceTheDelayPasses() {
        let (sut, scheduler) = makeSUT()
        XCTAssertFalse(sut.isHidden, "visible before anything happens")

        sut.reveal()
        XCTAssertFalse(sut.isHidden, "visible as the text appears")
        XCTAssertEqual(scheduler.delays, [.seconds(3)])

        scheduler.elapse()
        XCTAssertTrue(sut.isHidden, "hidden once the delay passes with no interaction")
    }

    func test_reveal_whileHidden_bringsThemBack_andStartsTheDelayAgain() {
        let (sut, scheduler) = makeSUT()
        sut.reveal()
        scheduler.elapse()

        sut.reveal()
        XCTAssertFalse(sut.isHidden, "a tap brings them back")
        XCTAssertEqual(scheduler.pendingCount, 1, "and starts the delay again")

        scheduler.elapse()
        XCTAssertTrue(sut.isHidden)
    }

    /// Each interaction starts the delay from scratch: the earlier hide is cancelled, not left to
    /// fire early.
    func test_interaction_restartsTheDelay() {
        let (sut, scheduler) = makeSUT()
        sut.reveal()
        sut.reveal()
        sut.reveal()

        XCTAssertEqual(scheduler.delays.count, 3)
        XCTAssertEqual(scheduler.pendingCount, 1, "only the latest hide is pending")
    }

    func test_pinned_bringsThemBack_andNeverHides() {
        let (sut, scheduler) = makeSUT()
        sut.reveal()
        scheduler.elapse()

        sut.setPinned(true)
        XCTAssertFalse(sut.isHidden, "pinning brings them back")
        XCTAssertEqual(scheduler.pendingCount, 0, "and cancels the hide")

        sut.reveal()
        XCTAssertEqual(scheduler.pendingCount, 0, "no hide is scheduled while pinned")
        scheduler.elapse()
        XCTAssertFalse(sut.isHidden)
    }

    func test_pinnedBeforeAppearing_hidesNothing() {
        let (sut, scheduler) = makeSUT()
        sut.setPinned(true)
        sut.reveal()

        scheduler.elapse()
        XCTAssertFalse(sut.isHidden)
    }

    func test_unpinned_startsTheDelayAgain() {
        let (sut, scheduler) = makeSUT()
        sut.setPinned(true)
        sut.reveal()

        sut.setPinned(false)
        XCTAssertFalse(sut.isHidden)
        XCTAssertEqual(scheduler.pendingCount, 1, "the delay starts once nothing pins them")
        scheduler.elapse()
        XCTAssertTrue(sut.isHidden)
    }

    /// The same pin again (a re-render passing the same conditions) isn't an interaction.
    func test_samePinAgain_changesNothing() {
        let (sut, scheduler) = makeSUT()
        sut.reveal()
        scheduler.elapse()

        sut.setPinned(false)
        XCTAssertTrue(sut.isHidden, "an unchanged pin doesn't bring them back")
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func test_stop_cancelsTheHide() {
        let (sut, scheduler) = makeSUT()
        sut.reveal()

        sut.stop()
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    // MARK: - What pins them

    func test_pinned_onlyWhenSomethingNeedsThem() {
        let ready = ReadAlongControlsVisibility.isPinned(
            voiceOver: false, menuOpen: false, state: .ready, covered: false
        )
        XCTAssertFalse(ready, "the text is ready and nothing needs them: they hide")

        XCTAssertTrue(
            ReadAlongControlsVisibility.isPinned(voiceOver: true, menuOpen: false, state: .ready, covered: false),
            "VoiceOver users would lose them"
        )
        XCTAssertTrue(
            ReadAlongControlsVisibility.isPinned(voiceOver: false, menuOpen: true, state: .ready, covered: false),
            "the menu hangs off the label"
        )
        XCTAssertTrue(
            ReadAlongControlsVisibility.isPinned(voiceOver: false, menuOpen: false, state: .ready, covered: true),
            "the chapter panel or the full screen covers them"
        )
        let notReady: [ReadAlongState] = [
            .preparing, .downloadingModel("en-US"), .unsupported("xx"), .needsDownload, .fileMissing, .failed
        ]
        for state in notReady {
            XCTAssertTrue(
                ReadAlongControlsVisibility.isPinned(voiceOver: false, menuOpen: false, state: state, covered: false),
                "\(state): the label may be needed"
            )
        }
    }

    // MARK: - The real clock

    func test_sleepingScheduler_hidesAfterTheDelay() async throws {
        let sut = ReadAlongControlsVisibility(delay: .milliseconds(50))
        sut.reveal()

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(sut.isHidden)
    }

    func test_sleepingScheduler_interactionCancelsTheEarlierHide() async throws {
        let sut = ReadAlongControlsVisibility(delay: .milliseconds(300))
        sut.reveal()
        try await Task.sleep(for: .milliseconds(200))
        sut.reveal()

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(sut.isHidden, "the first hide was cancelled by the interaction")
    }

    // MARK: - The delay

    func test_defaultDelay_isThreeSeconds() {
        XCTAssertEqual(ReadAlongControlsVisibility.defaultDelay, .seconds(3))
    }

    #if DEBUG
    func test_hideAfterArgument_setsTheDelay() {
        let arguments = ["/path/to/Abbay", LaunchArgument.readAlongControlsHideAfter, "1.5"]

        XCTAssertEqual(DebugOverrides.readAlongControlsHideAfter(arguments: arguments), .milliseconds(1500))
    }

    func test_hideAfterArgument_absentOrUnreadable_isNil() {
        XCTAssertNil(DebugOverrides.readAlongControlsHideAfter(arguments: ["/path/to/Abbay"]))
        XCTAssertNil(DebugOverrides.readAlongControlsHideAfter(arguments: [LaunchArgument.readAlongControlsHideAfter]))
        XCTAssertNil(
            DebugOverrides.readAlongControlsHideAfter(arguments: [LaunchArgument.readAlongControlsHideAfter, "soon"])
        )
    }
    #endif
}

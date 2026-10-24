//
//  SiriBackgroundRefreshTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The daily `BGAppRefreshTask` that re-publishes Siri's context while the app isn't used (#127).
final class SiriBackgroundRefreshTests: XCTestCase {
    private let scheduler = FakeBackgroundRefreshScheduler()
    private let refresher = MockSiriContextRefresher()
    private let now = Date(timeIntervalSinceReferenceDate: 1000)

    private func makeRefresh() -> SiriBackgroundRefresh {
        SiriBackgroundRefresh(scheduler: scheduler, refresher: refresher, now: { [now] in now })
    }

    /// The identifier must also be in `BGTaskSchedulerPermittedIdentifiers`, or registering traps.
    func test_identifier_isPermittedInTheInfoPlist() throws {
        let permitted = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        )
        XCTAssertTrue(permitted.contains(SiriBackgroundRefresh.identifier))
    }

    func test_backgroundModes_includeFetch_besideAudio() throws {
        let modes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        XCTAssertTrue(modes.contains("fetch"))
        XCTAssertTrue(modes.contains("audio"))
    }

    func test_register_registersTheIdentifier() {
        makeRefresh().register()

        XCTAssertEqual(scheduler.registeredIdentifiers, [SiriBackgroundRefresh.identifier])
    }

    func test_schedule_submitsADayOut() throws {
        makeRefresh().schedule()

        let submission = try XCTUnwrap(scheduler.submissions.first)
        XCTAssertEqual(scheduler.submissions.count, 1)
        XCTAssertEqual(submission.identifier, SiriBackgroundRefresh.identifier)
        XCTAssertEqual(submission.earliestBeginDate, now.addingTimeInterval(24 * 60 * 60))
    }

    /// The simulator, and a device with Background App Refresh off, refuse the request.
    func test_schedule_whenTheSystemRefuses_doesNotThrow() {
        scheduler.submitError = NSError(domain: "BGTaskSchedulerErrorDomain", code: 1)

        makeRefresh().schedule()

        XCTAssertTrue(scheduler.submissions.isEmpty)
    }

    func test_run_reschedules_publishes_andCompletesOnce() throws {
        let refresh = makeRefresh()
        refresh.register()
        let task = FakeBackgroundRefreshTask()

        try XCTUnwrap(scheduler.launchHandler)(task)

        XCTAssertEqual(scheduler.submissions.count, 1, "the next run is scheduled as this one starts")
        XCTAssertEqual(refresher.nowReasons, [.backgroundTask])
        XCTAssertEqual(task.completions, [true])
        XCTAssertNotNil(task.expirationHandler)
    }

    func test_expiration_completesUnsuccessfully_andOnlyOnce() {
        let task = FakeBackgroundRefreshTask()
        refresher.onRefreshNow = { task.expirationHandler?() }

        makeRefresh().handle(task)
        task.expirationHandler?()

        XCTAssertEqual(task.completions, [false])
    }

    /// #159: Spotlight indexing finishes asynchronously, so the task waits for the publish to
    /// report completion before telling the system it is done.
    func test_run_completesOnlyAfterThePublishFinishes() {
        let task = FakeBackgroundRefreshTask()
        refresher.completesImmediately = false

        makeRefresh().handle(task)
        XCTAssertTrue(task.completions.isEmpty, "the publish is still indexing")

        refresher.finishPublishes()
        XCTAssertEqual(task.completions, [true])
    }

    /// Expiring while the publish is in flight completes unsuccessfully, and the publish finishing
    /// later doesn't complete the task a second time.
    func test_expirationWhileThePublishIsInFlight_completesOnce_unsuccessfully() {
        let task = FakeBackgroundRefreshTask()
        refresher.completesImmediately = false

        makeRefresh().handle(task)
        task.expirationHandler?()
        refresher.finishPublishes()

        XCTAssertEqual(task.completions, [false])
    }
}

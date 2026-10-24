//
//  AppDelegateSiriFreshnessTests.swift
//  AbbayTests
//

@testable import Abbay
import SwiftUI
import XCTest

/// The app's lifecycle hooks for Siri freshness (#127): register the background refresh at launch,
/// refresh the context on foreground, schedule the next background run on background.
final class AppDelegateSiriFreshnessTests: XCTestCase {
    private let scheduler = FakeBackgroundRefreshScheduler()
    private let refresher = MockSiriContextRefresher()

    override func tearDownWithError() throws {
        DependencyContainer.reset()
        try super.tearDownWithError()
    }

    private func makeDelegate() -> AppDelegate {
        DependencyContainer.reset()
        let delegate = AppDelegate()
        delegate.audioSessionActivator = OrderRecorderActivator {}
        delegate.seeder = OrderRecorderSeeder {}
        delegate.launchState = .inMemory()
        delegate.librarySnapshotWriter = MockLibrarySnapshotWriter()
        delegate.siriContext = refresher
        delegate.backgroundRefresh = SiriBackgroundRefresh(scheduler: scheduler, refresher: refresher)
        return delegate
    }

    func test_didFinishLaunching_registersTheBackgroundRefresh_andMarksLaunchPublished() {
        let delegate = makeDelegate()

        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertEqual(scheduler.registeredIdentifiers, [SiriBackgroundRefresh.identifier])
        XCTAssertEqual(refresher.markPublishedCount, 1)
    }

    func test_becomingActive_refreshesTheContextIfDue() {
        let delegate = makeDelegate()

        delegate.scenePhaseChanged(to: .active)

        XCTAssertEqual(refresher.dueReasons, [.foreground])
        XCTAssertTrue(scheduler.submissions.isEmpty)
    }

    func test_enteringTheBackground_schedulesTheNextBackgroundRefresh() {
        let delegate = makeDelegate()

        delegate.scenePhaseChanged(to: .background)

        XCTAssertEqual(scheduler.submissions.map(\.identifier), [SiriBackgroundRefresh.identifier])
        XCTAssertTrue(refresher.dueReasons.isEmpty)
    }

    func test_inactive_doesNothing() {
        let delegate = makeDelegate()

        delegate.scenePhaseChanged(to: .inactive)

        XCTAssertTrue(refresher.dueReasons.isEmpty)
        XCTAssertTrue(scheduler.submissions.isEmpty)
    }
}

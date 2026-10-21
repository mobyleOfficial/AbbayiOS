//
//  PlayerObserverTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// #94: the two subscription paths were asymmetric. `subscribeToTimePublisher` was guarded
/// against double-registration and had a matching cancel; `subscribeToPlayUrlPublisher` had
/// neither, so `CarPlaySceneDelegate.setupObservers` was not idempotent and
/// `didDisconnectInterfaceController` could only tear down half of what it set up.
final class PlayerObserverTests: XCTestCase {
    private var player = MockPlayer()
    private var observer: PlayerObserver?

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        observer = PlayerObserver(player)
    }

    // MARK: - URL subscription

    func test_subscribeToPlayUrl_isIdempotent() throws {
        let observer = try XCTUnwrap(self.observer)
        var calls = 0
        observer.subscribeToPlayUrlPublisher { _ in calls += 1 }
        observer.subscribeToPlayUrlPublisher { _ in calls += 1 }

        player.emitPlayUrl(AudioModel(title: "Book"))

        XCTAssertEqual(calls, 1, "a second subscribe must not stack another closure")
    }

    func test_cancelUrlSubscription_stopsDelivery() throws {
        let observer = try XCTUnwrap(self.observer)
        var calls = 0
        observer.subscribeToPlayUrlPublisher { _ in calls += 1 }

        observer.cancelUrlSubscription()
        player.emitPlayUrl(AudioModel(title: "Book"))

        XCTAssertEqual(calls, 0)
    }

    func test_cancelUrlSubscription_allowsResubscribing() throws {
        let observer = try XCTUnwrap(self.observer)
        var calls = 0
        observer.subscribeToPlayUrlPublisher { _ in calls += 1 }
        observer.cancelUrlSubscription()

        observer.subscribeToPlayUrlPublisher { _ in calls += 1 }
        player.emitPlayUrl(AudioModel(title: "Book"))

        XCTAssertEqual(calls, 1, "the guard must not permanently block resubscription")
    }

    // MARK: - Time subscription (already symmetric; pinned so it stays that way)

    func test_subscribeToTime_isIdempotent() throws {
        let observer = try XCTUnwrap(self.observer)
        var calls = 0
        observer.subscribeToTimePublisher { _ in calls += 1 }
        observer.subscribeToTimePublisher { _ in calls += 1 }

        player.emitTime(10)

        XCTAssertEqual(calls, 1)
    }

    func test_cancelTimeSubscription_stopsDeliveryAndAllowsResubscribing() throws {
        let observer = try XCTUnwrap(self.observer)
        var calls = 0
        observer.subscribeToTimePublisher { _ in calls += 1 }
        observer.cancelTimeSubscription()
        player.emitTime(10)
        XCTAssertEqual(calls, 0)

        observer.subscribeToTimePublisher { _ in calls += 1 }
        player.emitTime(20)

        XCTAssertEqual(calls, 1)
    }

    /// The two paths are independent: cancelling one must not silence the other.
    func test_cancellingOneSubscriptionLeavesTheOtherAlive() throws {
        let observer = try XCTUnwrap(self.observer)
        var urlCalls = 0
        var timeCalls = 0
        observer.subscribeToPlayUrlPublisher { _ in urlCalls += 1 }
        observer.subscribeToTimePublisher { _ in timeCalls += 1 }

        observer.cancelTimeSubscription()
        player.emitPlayUrl(AudioModel(title: "Book"))
        player.emitTime(10)

        XCTAssertEqual(urlCalls, 1, "cancelling time must not cancel the URL subscription")
        XCTAssertEqual(timeCalls, 0)
    }
}

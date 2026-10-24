//
//  AppDelegateOrderingTests.swift
//  AbbayTests
//

@testable import Abbay
import UIKit
import XCTest

final class OrderRecorderActivator: AudioSessionActivatorProtocol {
    let recorder: () -> Void

    init(recorder: @escaping () -> Void) { self.recorder = recorder }
    func activate() throws { recorder() }
}

final class OrderRecorderSeeder: AppDelegateSeederProtocol {
    let recorder: () -> Void

    init(recorder: @escaping () -> Void) { self.recorder = recorder }
    func seedIfNeeded() { recorder() }
}

final class AppDelegateOrderingTests: XCTestCase {
    // NOTE: DI-first ordering is a code-reading invariant (line 1 of didFinishLaunching is
    // `DependencyContainer.configure()`), not a runtime-observable one without instrumenting
    // DependencyContainer. We verify the runtime-observable part: audio session activates
    // before eager seed runs.
    func test_didFinishLaunching_audioSessionBeforeSeed() {
        var sequence: [String] = []
        DependencyContainer.reset()

        let delegate = AppDelegate()
        delegate.audioSessionActivator = OrderRecorderActivator { sequence.append("session") }
        delegate.seeder = OrderRecorderSeeder { sequence.append("seed") }
        delegate.launchState = .inMemory()

        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertEqual(sequence, ["session", "seed"])
    }

    func test_didFinishLaunching_audioSessionThrows_setsFlag_skipsSeed() throws {
        var seedCalled = false
        DependencyContainer.reset()

        let flag = LaunchStateFlag.inMemory()

        struct ThrowingActivator: AudioSessionActivatorProtocol {
            func activate() throws { throw NSError(domain: "test", code: 1) }
        }

        let delegate = AppDelegate()
        delegate.audioSessionActivator = ThrowingActivator()
        delegate.seeder = OrderRecorderSeeder { seedCalled = true }
        delegate.launchState = flag

        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)

        XCTAssertTrue(flag.isUnavailable())
        XCTAssertFalse(seedCalled)
    }
}

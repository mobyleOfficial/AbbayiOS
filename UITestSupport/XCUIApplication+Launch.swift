//
//  XCUIApplication+Launch.swift
//  AbbayUITests, AbbayAudioDomainUITests
//

import XCTest

extension XCUIApplication {
    /// `launch()`, tried once more when the simulator fails it for a reason that is not the app's
    /// (#210): "Failed to get background assertion for target app ... Timed out while acquiring
    /// background assertion", seen on a cold iOS 27.0 simulator. XCTest records that as a test
    /// failure from inside `launch()`, so `-retry-tests-on-failure` can't see it coming and a
    /// launch failure takes the whole test down. Only that failure is expected on the first
    /// attempt: any other issue still fails the test, and so does a second timeout.
    func launchRetryingOnce() {
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { issue in
            issue.compactDescription.contains("background assertion")
        }
        XCTExpectFailure("launch may time out acquiring a background assertion (#210)", options: options) {
            launch()
        }
        guard state != .runningForeground else { return }
        terminate()
        launch()
    }
}

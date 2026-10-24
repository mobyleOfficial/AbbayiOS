//
//  MockSiriFreshness.swift
//  AbbayTests
//

@testable import Abbay
import Foundation

final class MockSiriContextRefresher: SiriContextRefreshing {
    private(set) var dueReasons: [SiriRefreshReason] = []
    private(set) var nowReasons: [SiriRefreshReason] = []
    private(set) var markPublishedCount = 0
    /// Runs inside `refreshNow`, to act while a background task is in flight.
    var onRefreshNow: (() -> Void)?
    /// When false, `refreshNow`'s completion waits in `pendingCompletions` until a test finishes
    /// the publish with `finishPublishes()`, as Spotlight's indexing does in the real publish.
    var completesImmediately = true
    private(set) var pendingCompletions: [() -> Void] = []

    func refreshIfDue(_ reason: SiriRefreshReason) { dueReasons.append(reason) }

    func refreshNow(_ reason: SiriRefreshReason, completion: @escaping () -> Void) {
        nowReasons.append(reason)
        onRefreshNow?()
        if completesImmediately {
            completion()
        } else {
            pendingCompletions.append(completion)
        }
    }

    func finishPublishes() {
        let completions = pendingCompletions
        pendingCompletions = []
        completions.forEach { $0() }
    }

    func markPublished() { markPublishedCount += 1 }
}

final class FakeBackgroundRefreshTask: BackgroundRefreshTask {
    var expirationHandler: (() -> Void)?
    private(set) var completions: [Bool] = []

    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }
}

final class FakeBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    struct Submission {
        let identifier: String
        let earliestBeginDate: Date
    }

    private(set) var registeredIdentifiers: [String] = []
    private(set) var launchHandler: ((BackgroundRefreshTask) -> Void)?
    private(set) var submissions: [Submission] = []
    var submitError: Error?

    func register(identifier: String, launchHandler: @escaping (BackgroundRefreshTask) -> Void) {
        registeredIdentifiers.append(identifier)
        self.launchHandler = launchHandler
    }

    func submit(identifier: String, earliestBeginDate: Date) throws {
        if let submitError { throw submitError }
        submissions.append(Submission(identifier: identifier, earliestBeginDate: earliestBeginDate))
    }
}

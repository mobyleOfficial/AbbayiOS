//
//  LoggedMessages.swift
//  AbbayTests
//

@testable import Abbay
import Foundation
import OSLog

/// Reads back what this test process wrote to the unified log, for tests that pin a `Log` call.
///
/// `composedMessage` is what Console shows: a `.private` argument may or may not be redacted
/// depending on the host, so a test asserts that a title is absent from the message altogether
/// (which only holds when it is never logged), not that it reads `<private>`.
enum LoggedMessages {
    /// Messages in `category` logged at or after `since`, read again until one contains `marker`
    /// or `timeout` passes: entries reach the store asynchronously, so a read straight after the
    /// log call can miss them.
    static func messages(
        category: String,
        since: Date,
        awaiting marker: String,
        timeout: TimeInterval = 5
    ) throws -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var messages = try messages(category: category, since: since)
        while !messages.contains(where: { $0.contains(marker) }), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            messages = try self.messages(category: category, since: since)
        }
        return messages
    }

    /// Messages in `category` of the app's subsystem logged at or after `since`.
    static func messages(category: String, since: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let subsystem = Bundle.main.bundleIdentifier ?? "com.edyuto.Abbay"
        // The whole process's log, filtered by date: `position(date:)` proved unreliable, starting
        // past entries written seconds later.
        return try store.getEntries()
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.date >= since && $0.subsystem == subsystem && $0.category == category }
            .map(\.composedMessage)
    }
}

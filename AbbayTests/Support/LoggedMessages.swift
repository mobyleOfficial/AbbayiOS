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
    /// Messages in `category` of the app's subsystem logged at or after `since`.
    static func messages(category: String, since: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let subsystem = Bundle.main.bundleIdentifier ?? "com.edyuto.Abbay"
        return try store.getEntries(at: store.position(date: since))
            .compactMap { $0 as? OSLogEntryLog }
            // `position(date:)` is coarse: it can start before `since`.
            .filter { $0.date >= since && $0.subsystem == subsystem && $0.category == category }
            .map(\.composedMessage)
    }
}

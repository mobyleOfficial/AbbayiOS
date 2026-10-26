//
//  MockNoticeReporter.swift
//  AbbayTests
//

@testable import Abbay
import Foundation

/// Records every reported notice. Thread-safe: the player reports from AVFoundation's queues.
final class MockNoticeReporter: NoticeReporting {
    private let lock = NSLock()
    private var reported: [Notice] = []
    /// Called after each report, on the reporting thread.
    var onReport: ((Notice) -> Void)?

    var notices: [Notice] {
        lock.withLock { reported }
    }

    func report(_ notice: Notice) {
        lock.withLock { reported.append(notice) }
        onReport?(notice)
    }
}

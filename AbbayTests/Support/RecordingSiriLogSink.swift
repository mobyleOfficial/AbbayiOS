//
//  RecordingSiriLogSink.swift
//  AbbayTests
//

@testable import Abbay
import Foundation

/// Captures what a class under test logs, in place of `OSSiriLogSink`. Tests used to read the
/// unified log back through `OSLogStore`, which missed entries in full-suite runs (#181).
final class RecordingSiriLogSink: SiriLogSink {
    private let lock = NSLock()
    private var recorded: [SiriLogEvent] = []

    var events: [SiriLogEvent] {
        lock.withLock { recorded }
    }

    func log(_ event: SiriLogEvent) {
        lock.withLock { recorded.append(event) }
    }
}

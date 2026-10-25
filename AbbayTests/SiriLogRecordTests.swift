//
//  SiriLogRecordTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Pins the exact text, level and privacy `OSSiriLogSink` writes for each `SiriLogEvent` (#190).
/// The feature map and anyone reading a sysdiagnose search for these strings, so a typo or a switch
/// to `.private` must fail here. Pure values only: no unified-log reads (#181).
final class SiriLogRecordTests: XCTestCase {
    func test_donationFailed_isPublicErrorWithDomainAndCode() {
        XCTAssertEqual(
            SiriLogEvent.donationFailed(domain: "IntentsErrorDomain", code: 1901).record,
            SiriLogRecord(level: .error, message: "donation failed: IntentsErrorDomain 1901", privacy: .public)
        )
    }

    func test_donationFailed_fromNSError_keepsOnlyDomainAndCode() {
        let error = NSError(domain: "D", code: -7, userInfo: [NSLocalizedDescriptionKey: "Harry Potter.m4b"])
        let record = SiriLogEvent.donationFailed(error).record
        XCTAssertEqual(record.message, "donation failed: D -7")
        XCTAssertFalse(record.message.contains("Harry Potter"))
    }

    func test_publishStarted_isPublicInfoWithCount() {
        XCTAssertEqual(
            SiriLogEvent.publishStarted(bookCount: 2).record,
            SiriLogRecord(level: .info, message: "publish: 2 books", privacy: .public)
        )
        XCTAssertEqual(SiriLogEvent.publishStarted(bookCount: 0).record.message, "publish: 0 books")
    }

    func test_publishFinished_isPublicDebug() {
        XCTAssertEqual(
            SiriLogEvent.publishFinished.record,
            SiriLogRecord(level: .debug, message: "publish: finished", privacy: .public)
        )
    }

    func test_spotlightIndexingFailed_isPublicErrorWithDomainAndCode() {
        XCTAssertEqual(
            SiriLogEvent.spotlightIndexingFailed(domain: "CSIndexErrorDomain", code: -1003).record,
            SiriLogRecord(
                level: .error,
                message: "spotlight indexing failed: CSIndexErrorDomain -1003",
                privacy: .public
            )
        )
    }
}

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

    /// #173: the end of a publish carries its duration, at `.info` so a device's log keeps it.
    func test_publishFinished_isPublicInfoWithTheDuration() {
        XCTAssertEqual(
            SiriLogEvent.publishFinished(milliseconds: 1234).record,
            SiriLogRecord(level: .info, message: "publish: finished in 1234 ms", privacy: .public)
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

    /// #195: a publish clears the index before indexing; a failed clear is logged like a failed index.
    func test_spotlightClearingFailed_isPublicErrorWithDomainAndCode() {
        XCTAssertEqual(
            SiriLogEvent.spotlightClearingFailed(domain: "CSIndexErrorDomain", code: -1003).record,
            SiriLogRecord(
                level: .error,
                message: "spotlight clearing failed: CSIndexErrorDomain -1003",
                privacy: .public
            )
        )
    }

    // MARK: - Context and background refresh (#197)

    func test_contextRefreshSkipped_isPublicDebugWithReason() {
        XCTAssertEqual(
            SiriLogEvent.contextRefreshSkipped(reason: SiriRefreshReason.pause.rawValue).record,
            SiriLogRecord(level: .debug, message: "context refresh skipped (pause): throttled", privacy: .public)
        )
    }

    func test_contextRefreshed_isPublicInfoWithReasonAndCount() {
        XCTAssertEqual(
            SiriLogEvent.contextRefreshed(reason: SiriRefreshReason.foreground.rawValue, bookCount: 3).record,
            SiriLogRecord(level: .info, message: "context refresh (foreground): 3 books", privacy: .public)
        )
    }

    func test_backgroundRefreshRegistrationRefused_isPublicErrorWithIdentifier() {
        XCTAssertEqual(
            SiriLogEvent.backgroundRefreshRegistrationRefused(identifier: SiriBackgroundRefresh.identifier).record,
            SiriLogRecord(
                level: .error,
                message: "background refresh: registration refused for com.edyuto.Abbay.siriRefresh",
                privacy: .public
            )
        )
    }

    func test_backgroundRefreshNotScheduled_keepsOnlyDomainAndCode() {
        let error = NSError(domain: "BGTaskSchedulerErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "x"])
        XCTAssertEqual(
            SiriLogEvent.backgroundRefreshNotScheduled(error).record,
            SiriLogRecord(
                level: .error,
                message: "background refresh: not scheduled: BGTaskSchedulerErrorDomain 1",
                privacy: .public
            )
        )
    }

    func test_backgroundRefreshExpiredAndFinished_arePublicInfo() {
        XCTAssertEqual(
            SiriLogEvent.backgroundRefreshExpired.record,
            SiriLogRecord(level: .info, message: "background refresh: expired", privacy: .public)
        )
        XCTAssertEqual(
            SiriLogEvent.backgroundRefreshPublishFinished.record,
            SiriLogRecord(level: .info, message: "background refresh: publish finished", privacy: .public)
        )
    }

    // MARK: - Library snapshot (#197)

    func test_snapshotWritten_isPublicInfoWithCountsAndSuite() {
        XCTAssertEqual(
            LibrarySnapshotLogEvent
                .written(entryCount: 4, bookmarkCount: 3, suiteName: "group.com.edyuto.abbay")
                .record,
            SiriLogRecord(
                level: .info,
                message: "snapshot WRITTEN: 4 entries (3 with bookmark), suite=group.com.edyuto.abbay",
                privacy: .public
            )
        )
    }

    func test_snapshotEncodeFailed_isPublicError() {
        XCTAssertEqual(
            LibrarySnapshotLogEvent.encodeFailed.record,
            SiriLogRecord(level: .error, message: "snapshot WRITE FAILED: JSON encode error", privacy: .public)
        )
    }

    // MARK: - Incremental Spotlight (#173)

    /// A publish deletes only the items that left the library.
    func test_spotlightDeletingFailed_isPublicErrorWithDomainAndCode() {
        XCTAssertEqual(
            SiriLogEvent.spotlightDeletingFailed(domain: "CSIndexErrorDomain", code: -1003).record,
            SiriLogRecord(
                level: .error,
                message: "spotlight deleting failed: CSIndexErrorDomain -1003",
                privacy: .public
            )
        )
    }

    /// What each publish did to the index, in counts.
    func test_spotlightUnchanged_isPublicDebugWithTheCount() {
        XCTAssertEqual(
            SiriLogEvent.spotlightUnchanged(itemCount: 15).record,
            SiriLogRecord(level: .debug, message: "spotlight: unchanged, 15 items", privacy: .public)
        )
    }

    func test_spotlightUpdated_isPublicInfoWithTheCounts() {
        XCTAssertEqual(
            SiriLogEvent.spotlightUpdated(indexed: 1, deleted: 2).record,
            SiriLogRecord(level: .info, message: "spotlight: indexed 1, deleted 2", privacy: .public)
        )
    }

    func test_spotlightRebuilt_isPublicInfoWithTheCountAndReason() {
        XCTAssertEqual(
            SiriLogEvent.spotlightRebuilt(itemCount: 15, reason: .noRecord).record,
            SiriLogRecord(level: .info, message: "spotlight: rebuilt, 15 items (no record)", privacy: .public)
        )
        XCTAssertEqual(
            SiriLogEvent.spotlightRebuilt(itemCount: 3, reason: .afterFailure).record.message,
            "spotlight: rebuilt, 3 items (after a failure)"
        )
        XCTAssertEqual(
            SiriLogEvent.spotlightRebuilt(itemCount: 2, reason: .reindexRequested).record.message,
            "spotlight: rebuilt, 2 items (the system asked)"
        )
    }

    /// #205.
    func test_spotlightReindexRequested_isPublicInfo() {
        XCTAssertEqual(
            SiriLogEvent.spotlightReindexRequested(itemCount: nil).record,
            SiriLogRecord(level: .info, message: "spotlight: the system asked to re-index everything", privacy: .public)
        )
        XCTAssertEqual(
            SiriLogEvent.spotlightReindexRequested(itemCount: 4).record.message,
            "spotlight: the system asked to re-index 4 items"
        )
    }
}

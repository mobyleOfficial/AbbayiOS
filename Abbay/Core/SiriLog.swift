//
//  SiriLog.swift
//  Abbay
//

import Foundation

/// Something the Siri publishing and donation code reports to the unified log (#157).
///
/// The cases carry only what may be logged publicly: counts and an error's domain and code. A
/// title has nowhere to go, so the privacy decision is made here, by the type, rather than at each
/// call site; `OSSiriLogSink` writes every field `privacy: .public`.
enum SiriLogEvent: Equatable {
    /// A failed `INInteraction` donation. A failure silently stops Siri learning to prefer Abbay.
    case donationFailed(domain: String, code: Int)
    /// A library publish started, with the number of books (never their titles).
    case publishStarted(bookCount: Int)
    /// A publish's asynchronous part (Spotlight indexing) finished.
    case publishFinished
    /// Core Spotlight refused the library's items.
    case spotlightIndexingFailed(domain: String, code: Int)
    /// Core Spotlight didn't clear the library's previous items before re-indexing (#195): books
    /// deleted since may still show until the next publish clears them.
    case spotlightClearingFailed(domain: String, code: Int)
    /// A foreground/pause/interruption/CarPlay refresh came within `minimumInterval` of the last
    /// publish and was skipped (`SiriContextRefresher`, #127). `reason` is a `SiriRefreshReason`.
    case contextRefreshSkipped(reason: String)
    /// A context refresh published the library: why, and how many books.
    case contextRefreshed(reason: String, bookCount: Int)
    /// `BGTaskScheduler` refused to register the background refresh's identifier.
    case backgroundRefreshRegistrationRefused(identifier: String)
    /// The background refresh couldn't be scheduled (expected on the simulator, and with Background
    /// App Refresh off).
    case backgroundRefreshNotScheduled(domain: String, code: Int)
    /// The system expired a background refresh before its publish finished.
    case backgroundRefreshExpired
    /// A background refresh's publish finished.
    case backgroundRefreshPublishFinished

    /// The domain and code only: an error's description can carry a title or a file path.
    static func donationFailed(_ error: NSError) -> SiriLogEvent {
        .donationFailed(domain: error.domain, code: error.code)
    }

    static func spotlightIndexingFailed(_ error: NSError) -> SiriLogEvent {
        .spotlightIndexingFailed(domain: error.domain, code: error.code)
    }

    static func spotlightClearingFailed(_ error: NSError) -> SiriLogEvent {
        .spotlightClearingFailed(domain: error.domain, code: error.code)
    }

    static func backgroundRefreshNotScheduled(_ error: NSError) -> SiriLogEvent {
        .backgroundRefreshNotScheduled(domain: error.domain, code: error.code)
    }
}

/// Where `SiriLogEvent`s go. Production writes them to `Log.siri`; tests inject a recorder, so
/// they assert on what was logged without reading the unified log back (#181).
protocol SiriLogSink {
    func log(_ event: SiriLogEvent)
}

/// Writes events to `Log.siri` (`os.Logger`, category "Siri"), with the messages and levels the
/// app has always used. A thin wrapper: the text, level and privacy come from
/// `SiriLogEvent.record`, which is what the tests pin (#190).
struct OSSiriLogSink: SiriLogSink {
    func log(_ event: SiriLogEvent) {
        Log.siri.write(event.record)
    }
}

extension SiriLogEvent {
    /// The record `OSSiriLogSink` writes. Every event is `.public`: the cases carry only counts,
    /// refresh reasons, a task identifier and error domains/codes, never a title.
    var record: SiriLogRecord {
        switch self {
        case let .donationFailed(domain, code):
            SiriLogRecord(level: .error, message: "donation failed: \(domain) \(code)", privacy: .public)
        case let .publishStarted(bookCount):
            SiriLogRecord(level: .info, message: "publish: \(bookCount) books", privacy: .public)
        case .publishFinished:
            SiriLogRecord(level: .debug, message: "publish: finished", privacy: .public)
        case let .spotlightIndexingFailed(domain, code):
            SiriLogRecord(level: .error, message: "spotlight indexing failed: \(domain) \(code)", privacy: .public)
        case let .spotlightClearingFailed(domain, code):
            SiriLogRecord(level: .error, message: "spotlight clearing failed: \(domain) \(code)", privacy: .public)
        case let .contextRefreshSkipped(reason):
            SiriLogRecord(level: .debug, message: "context refresh skipped (\(reason)): throttled", privacy: .public)
        case let .contextRefreshed(reason, bookCount):
            SiriLogRecord(level: .info, message: "context refresh (\(reason)): \(bookCount) books", privacy: .public)
        case let .backgroundRefreshRegistrationRefused(identifier):
            SiriLogRecord(
                level: .error,
                message: "background refresh: registration refused for \(identifier)",
                privacy: .public
            )
        case let .backgroundRefreshNotScheduled(domain, code):
            SiriLogRecord(level: .error, message: "background refresh: not scheduled: \(domain) \(code)", privacy: .public)
        case .backgroundRefreshExpired:
            SiriLogRecord(level: .info, message: "background refresh: expired", privacy: .public)
        case .backgroundRefreshPublishFinished:
            SiriLogRecord(level: .info, message: "background refresh: publish finished", privacy: .public)
        }
    }
}

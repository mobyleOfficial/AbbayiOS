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
        let record = event.record
        // `os.Logger` fixes privacy per interpolation at compile time, so each combination is
        // spelled out rather than passed as a value.
        switch (record.level, record.privacy) {
        case (.debug, .public): Log.siri.debug("\(record.message, privacy: .public)")
        case (.debug, .private): Log.siri.debug("\(record.message, privacy: .private)")
        case (.info, .public): Log.siri.info("\(record.message, privacy: .public)")
        case (.info, .private): Log.siri.info("\(record.message, privacy: .private)")
        case (.error, .public): Log.siri.error("\(record.message, privacy: .public)")
        case (.error, .private): Log.siri.error("\(record.message, privacy: .private)")
        }
    }
}

/// The `os.Logger` level a `SiriLogRecord` is written at.
enum SiriLogLevel: Equatable {
    case debug, info, error
}

/// Whether a record's message shows in the unified log (`.public`) or is redacted to `<private>`
/// (`.private`).
enum SiriLogPrivacy: Equatable {
    case `public`, `private`
}

/// Exactly what `OSSiriLogSink` writes for one event. A pure value, so tests pin the text a
/// sysdiagnose shows without reading the unified log back (#181, #190).
struct SiriLogRecord: Equatable {
    let level: SiriLogLevel
    let message: String
    let privacy: SiriLogPrivacy
}

extension SiriLogEvent {
    /// The record `OSSiriLogSink` writes. Every event is `.public`: the cases carry only counts and
    /// error domains/codes, never a title.
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
        }
    }
}

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

    /// The domain and code only: an error's description can carry a title or a file path.
    static func donationFailed(_ error: NSError) -> SiriLogEvent {
        .donationFailed(domain: error.domain, code: error.code)
    }

    static func spotlightIndexingFailed(_ error: NSError) -> SiriLogEvent {
        .spotlightIndexingFailed(domain: error.domain, code: error.code)
    }
}

/// Where `SiriLogEvent`s go. Production writes them to `Log.siri`; tests inject a recorder, so
/// they assert on what was logged without reading the unified log back (#181).
protocol SiriLogSink {
    func log(_ event: SiriLogEvent)
}

/// Writes events to `Log.siri` (`os.Logger`, category "Siri"), with the messages and levels the
/// app has always used.
struct OSSiriLogSink: SiriLogSink {
    func log(_ event: SiriLogEvent) {
        switch event {
        case let .donationFailed(domain, code):
            Log.siri.error("donation failed: \(domain, privacy: .public) \(code, privacy: .public)")
        case let .publishStarted(bookCount):
            Log.siri.info("publish: \(bookCount, privacy: .public) books")
        case .publishFinished:
            Log.siri.debug("publish: finished")
        case let .spotlightIndexingFailed(domain, code):
            Log.siri.error("spotlight indexing failed: \(domain, privacy: .public) \(code, privacy: .public)")
        }
    }
}

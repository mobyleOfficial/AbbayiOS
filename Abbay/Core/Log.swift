//
//  Log.swift
//  Abbay
//

import Foundation
import os

/// The app's `os.Logger`s, one category per area. Every log call in the app and the AbbayIntents
/// extension goes through these, so the file is compiled into both targets and uses only
/// Foundation and `os`, which are extension-safe.
///
/// The subsystem is the running bundle's identifier: `com.edyuto.Abbay` in the app,
/// `com.edyuto.Abbay.AbbayIntents` in the extension. Code shared by both (`AppGroup`,
/// `LibrarySnapshotWriter`) therefore logs under the process it runs in.
///
/// User content (file names, titles, spoken media names, URLs) is `privacy: .private`; counts,
/// flags and error domains/codes are `.public`. Error descriptions are not logged, since they can
/// carry a file path.
///
/// `SiriDiagnostics` is not behind this facade on purpose. The unified log can't be read off a
/// locked device without root, so that ring buffer lives in the App Group and is read by copying
/// the container off the phone (#87).
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.edyuto.Abbay"

    static let player = Logger(subsystem: subsystem, category: "Player")
    static let importing = Logger(subsystem: subsystem, category: "Import")
    static let data = Logger(subsystem: subsystem, category: "CoreData")
    static let bookmarks = Logger(subsystem: subsystem, category: "Bookmarks")
    static let nowPlaying = Logger(subsystem: subsystem, category: "NowPlaying")
    static let downloads = Logger(subsystem: subsystem, category: "Downloads")
    static let appGroup = Logger(subsystem: subsystem, category: "AppGroup")
    static let librarySnapshot = Logger(subsystem: subsystem, category: "LibrarySnapshot")
    static let playMediaIntent = Logger(subsystem: subsystem, category: "PlayMediaIntent")
    static let siri = Logger(subsystem: subsystem, category: "Siri")
    static let covers = Logger(subsystem: subsystem, category: "Covers")
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

/// Exactly what is written for one log event: `SiriLogEvent` (Siri publishing and donation) and
/// `LibrarySnapshotLogEvent`. A pure value, so tests pin the text a sysdiagnose shows without
/// reading the unified log back (#181, #190, #197). Here rather than in `SiriLog.swift` because the
/// snapshot writer is also compiled into the AbbayIntents extension.
struct SiriLogRecord: Equatable {
    let level: SiriLogLevel
    let message: String
    let privacy: SiriLogPrivacy
}

extension Logger {
    /// Writes `record` at its level and privacy. `os.Logger` fixes privacy per interpolation at
    /// compile time, so each combination is spelled out rather than passed as a value.
    func write(_ record: SiriLogRecord) {
        switch (record.level, record.privacy) {
        case (.debug, .public): debug("\(record.message, privacy: .public)")
        case (.debug, .private): debug("\(record.message, privacy: .private)")
        case (.info, .public): info("\(record.message, privacy: .public)")
        case (.info, .private): info("\(record.message, privacy: .private)")
        case (.error, .public): error("\(record.message, privacy: .public)")
        case (.error, .private): error("\(record.message, privacy: .private)")
        }
    }
}

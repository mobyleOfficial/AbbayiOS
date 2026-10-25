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

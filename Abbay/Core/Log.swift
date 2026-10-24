//
//  Log.swift
//  Abbay
//

import Foundation
import os

/// The app's `os.Logger`s, one category per area. The call sites that report a `Notice` log
/// through these; the rest of the app's `print`s move here with #87.
///
/// Like `LibrarySnapshotWriter`: user content (file names, titles) is `privacy: .private`, counts,
/// flags and error domains/codes are `.public`. Error descriptions are not logged, since they can
/// carry a file path.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.edyuto.Abbay"

    static let player = Logger(subsystem: subsystem, category: "Player")
    static let importing = Logger(subsystem: subsystem, category: "Import")
    static let data = Logger(subsystem: subsystem, category: "CoreData")
}

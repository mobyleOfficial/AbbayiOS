//
//  AppGroup.swift
//  Abbay
//

import Foundation
import os.log

private let appGroupLog = OSLog(subsystem: "com.edyuto.Abbay", category: "AppGroup")

enum AppGroup {
    static let suiteName: String = "group.com.edyuto.abbay"

    /// The key-value store the app and the Siri extension share: last played, the launch flag,
    /// the library snapshot and the diagnostics trail. Production default for those types; tests
    /// inject an `InMemoryKeyValueStore` instead.
    static let store: KeyValueStoring = makeStore()

    /// Fails soft rather than trapping. `UserDefaults(suiteName:)` returns nil only for a reserved
    /// name (the app's own bundle identifier, or `NSGlobalDomain`); a missing App Group
    /// entitlement still returns a store, just not a shared one. So nil means a bad name, and a
    /// crash there would take the Siri extension down with it. A process-local store keeps both
    /// processes running, without the cross-process hand-off, and the fault says why.
    static func makeStore(suiteName: String = suiteName) -> KeyValueStoring {
        if let defaults = UserDefaults(suiteName: suiteName) {
            return defaults
        }
        os_log(
            "App Group %{public}@ unavailable, using a process-local store: check the suite name",
            log: appGroupLog,
            type: .fault,
            suiteName
        )
        return InMemoryKeyValueStore()
    }
}

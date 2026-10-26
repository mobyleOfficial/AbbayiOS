//
//  AppDelegateSeeder.swift
//  Abbay
//

import Foundation

protocol AppDelegateSeederProtocol {
    func seedIfNeeded()
}

/// One-time migrations run at launch, once the audio session is up.
///
/// Only the last-played pointer is left: it moved from the app's own defaults to the App Group,
/// and a user upgrading still has it in the old place. The library snapshot is not seeded here
/// (#153): `AppDelegate` rewrites it on every launch, and every library mutation writes it
/// through the use cases, so a "write it if missing" step could only repeat the launch write.
final class AppDelegateSeeder: AppDelegateSeederProtocol {
    private let appGroup: KeyValueStoring
    private let standard: KeyValueStoring

    init(
        appGroup: KeyValueStoring = AppGroup.store,
        standard: KeyValueStoring = UserDefaults.standard
    ) {
        self.appGroup = appGroup
        self.standard = standard
    }

    func seedIfNeeded() {
        if appGroup.object(forKey: LastPlayedStore.key) as? String == nil,
           let standardValue = standard.object(forKey: LastPlayedStore.key) as? String {
            appGroup.set(standardValue, forKey: LastPlayedStore.key)
        }
    }
}

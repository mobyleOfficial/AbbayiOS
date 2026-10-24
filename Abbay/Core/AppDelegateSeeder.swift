//
//  AppDelegateSeeder.swift
//  Abbay
//

import Foundation

protocol AppDelegateSeederProtocol {
    func seedIfNeeded()
}

final class AppDelegateSeeder: AppDelegateSeederProtocol {
    private let appGroup: KeyValueStoring
    private let standard: KeyValueStoring
    private let snapshotWriter: LibrarySnapshotWriterProtocol

    init(
        appGroup: KeyValueStoring = AppGroup.store,
        standard: KeyValueStoring = UserDefaults.standard,
        snapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
    ) {
        self.appGroup = appGroup
        self.standard = standard
        self.snapshotWriter = snapshotWriter
    }

    func seedIfNeeded() {
        seedLastPlayedIfNeeded()
        seedLibrarySnapshotIfNeeded()
    }

    private func seedLastPlayedIfNeeded() {
        if appGroup.object(forKey: LastPlayedStore.key) as? String == nil,
           let standardValue = standard.object(forKey: LastPlayedStore.key) as? String {
            appGroup.set(standardValue, forKey: LastPlayedStore.key)
        }
    }

    private func seedLibrarySnapshotIfNeeded() {
        if appGroup.object(forKey: LibrarySnapshotWriter.key) as? Data == nil {
            snapshotWriter.refresh()
        }
    }
}

//
//  AppDelegateSeeder.swift
//  Abbay
//

import Foundation

protocol AppDelegateSeederProtocol {
    func seedIfNeeded()
}

final class AppDelegateSeeder: AppDelegateSeederProtocol {
    private let lastPlayedSuite: UserDefaults
    private let standard: UserDefaults
    private let snapshotWriter: LibrarySnapshotWriterProtocol

    init(
        lastPlayedSuite: UserDefaults = AppGroup.defaults,
        standard: UserDefaults = .standard,
        snapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
    ) {
        self.lastPlayedSuite = lastPlayedSuite
        self.standard = standard
        self.snapshotWriter = snapshotWriter
    }

    func seedIfNeeded() {
        seedLastPlayedIfNeeded()
        seedLibrarySnapshotIfNeeded()
    }

    private func seedLastPlayedIfNeeded() {
        if lastPlayedSuite.string(forKey: LastPlayedStore.key) == nil,
           let standardValue = standard.string(forKey: LastPlayedStore.key) {
            lastPlayedSuite.set(standardValue, forKey: LastPlayedStore.key)
        }
    }

    private func seedLibrarySnapshotIfNeeded() {
        if lastPlayedSuite.data(forKey: LibrarySnapshotWriter.key) == nil {
            snapshotWriter.refresh()
        }
    }
}

//
//  MovedBookKeyMigration.swift
//  Abbay
//

import Foundation
import os

/// Re-keys a per-book speed. `AppSettings` is the production one.
protocol BookSpeedRekeying: AnyObject {
    /// Moves the speed saved under `oldURL` to `newURL`, unless `newURL` has one already; either
    /// way nothing is left under `oldURL`. Any thread.
    func moveSpeed(from oldURL: URL, to newURL: URL)
}

/// What the migration rewrites.
struct MovedBookKeyStores {
    let lastPlayed: LastPlayedStore
    let speeds: BookSpeedRekeying
}

/// Moves the keys a moved book was saved under before #186 to its identity, the row's URL.
///
/// Until then the player keyed a loaded book by where its bookmark resolved, so a book whose file
/// had moved (or whose resolved URL was spelled differently) had its last-played pointer and its
/// speed saved under that URL, which matches no row. The library's loads hand every moved book
/// (`AudioModel.resolvedURL` set) here, so an upgrade keeps both (on-disk compatibility, #143).
/// Nothing writes those keys any more, so each book is looked at once per launch.
final class MovedBookKeyMigration {
    static let shared = MovedBookKeyMigration()

    /// Nil skips the migration: before the container is configured, and in the Siri extension.
    private let stores: () -> MovedBookKeyStores?
    private var migrated = Set<URL>()
    private let lock = NSLock()

    init(stores: @escaping () -> MovedBookKeyStores? = MovedBookKeyMigration.containerStores) {
        self.stores = stores
    }

    func migrate(_ books: [AudioModel]) {
        guard books.contains(where: { $0.resolvedURL != nil }), let stores = stores() else { return }
        let moved: [(url: URL, resolved: URL)] = lock.withLock {
            books.compactMap { book in
                guard let url = book.url, let resolved = book.resolvedURL, resolved != url,
                      migrated.insert(resolved).inserted else { return nil }
                return (url, resolved)
            }
        }
        for (url, resolved) in moved {
            if stores.lastPlayed.lastPlayedURL() == resolved {
                stores.lastPlayed.save(url: url)
                Log.bookmarks.info("moved the last-played pointer of a moved book to its row")
            }
            stores.speeds.moveSpeed(from: resolved, to: url)
        }
    }

    static func containerStores() -> MovedBookKeyStores? {
        guard DependencyContainer.isConfigured else { return nil }
        let container = DependencyContainer.shared
        return MovedBookKeyStores(lastPlayed: container.lastPlayed, speeds: container.settings)
    }
}

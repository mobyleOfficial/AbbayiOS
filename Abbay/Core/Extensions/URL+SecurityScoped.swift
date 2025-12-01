//
//  URL+SecurityScoped.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import Foundation

extension URL {
    /// Creates a security-scoped bookmark from this URL
    func createBookmarkData() -> Data? {
        // TODO: Add logging for bookmark creation using logging library
        do {
            // On iOS, use empty options for security-scoped resources from document picker
            let bookmarkData = try self.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            print("✅ Created security-scoped bookmark for: \(self.lastPathComponent)")
            return bookmarkData
        } catch {
            // TODO: Log bookmark creation failure
            print("❌ Failed to create bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolves a security-scoped bookmark to a URL
    static func resolveBookmark(from bookmarkData: Data?) -> URL? {
        guard let bookmarkData else { return nil }
        // TODO: Add logging for bookmark resolution using logging library
        var isStale = false
        do {
            // On iOS, use .withoutUI for resolving security-scoped bookmarks
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // TODO: Log stale bookmark
                print("⚠️ Bookmark is stale for: \(url.lastPathComponent)")
                // If stale, try to recreate the bookmark
                if url.createBookmarkData() != nil {
                    print("♻️ Recreated stale bookmark for: \(url.lastPathComponent)")
                }
            } else {
                print("✅ Resolved security-scoped bookmark for: \(url.lastPathComponent)")
            }
            return url
        } catch {
            // TODO: Log bookmark resolution failure
            print("❌ Failed to resolve bookmark: \(error.localizedDescription)")
            return nil
        }
    }
}

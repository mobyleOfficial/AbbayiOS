//
//  URL+SecurityScoped.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import Foundation
import os

extension URL {
    /// Creates a security-scoped bookmark from this URL
    func createBookmarkData() -> Data? {
        do {
            let bookmarkData = try self.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            Log.bookmarks.debug("created bookmark for \(self.lastPathComponent, privacy: .private)")
            return bookmarkData
        } catch {
            let error = error as NSError
            Log.bookmarks.error(
                """
                bookmark creation failed for \(self.lastPathComponent, privacy: .private): \
                \(error.domain, privacy: .public) \(error.code, privacy: .public)
                """
            )
            return nil
        }
    }

    /// Resolves a security-scoped bookmark to a URL. A bookmark that no longer resolves (the file
    /// was moved or deleted) returns nil: the caller falls back to the stored URL, and playing it
    /// reports the moved-file notice (#115), so nothing is reported here.
    static func resolveBookmark(from bookmarkData: Data?) -> URL? {
        guard let bookmarkData else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // The recreated bookmark isn't stored: this only checks that one can still be made.
                let recreated = url.createBookmarkData() != nil
                Log.bookmarks.info(
                    """
                    stale bookmark for \(url.lastPathComponent, privacy: .private), \
                    recreated=\(recreated, privacy: .public)
                    """
                )
            } else {
                Log.bookmarks.debug("resolved bookmark for \(url.lastPathComponent, privacy: .private)")
            }
            return url
        } catch {
            let error = error as NSError
            Log.bookmarks.error(
                "bookmark resolution failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)"
            )
            return nil
        }
    }
}

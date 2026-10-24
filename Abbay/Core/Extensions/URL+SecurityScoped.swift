//
//  URL+SecurityScoped.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import Foundation
import os

/// A resolved bookmark: the file it points at, and a new bookmark when the stored one was stale.
struct ResolvedBookmark: Equatable {
    let url: URL
    /// Non-nil only when the stored bookmark was stale and a new one could be made.
    let refreshedData: Data?
}

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
        resolveBookmarkRefreshing(from: bookmarkData)?.url
    }

    /// `resolveBookmark(from:)`, plus a new bookmark when the stored one resolved as stale. The
    /// caller saves it (#146): iOS can stop resolving a stale bookmark altogether, which would
    /// turn a book that plays today into a "moved or renamed" one.
    static func resolveBookmarkRefreshing(from bookmarkData: Data?) -> ResolvedBookmark? {
        guard let bookmarkData else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard isStale else {
                Log.bookmarks.debug("resolved bookmark for \(url.lastPathComponent, privacy: .private)")
                return ResolvedBookmark(url: url, refreshedData: nil)
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let refreshed = url.createBookmarkData()
            Log.bookmarks.info(
                """
                stale bookmark for \(url.lastPathComponent, privacy: .private), \
                recreated=\(refreshed != nil, privacy: .public)
                """
            )
            return ResolvedBookmark(url: url, refreshedData: refreshed)
        } catch {
            let error = error as NSError
            Log.bookmarks.error(
                "bookmark resolution failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)"
            )
            return nil
        }
    }
}

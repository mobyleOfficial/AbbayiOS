//
//  BookmarkProvider.swift
//  Abbay
//

import Foundation

protocol BookmarkProviderProtocol {
    func createBookmarkData(for url: URL) -> Data?
}

final class BookmarkProvider: BookmarkProviderProtocol {
    func createBookmarkData(for url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? url.bookmarkData(options: .minimalBookmark)
    }
}

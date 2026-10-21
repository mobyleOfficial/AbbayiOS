//
//  LibriVoxIdentity.swift
//  Abbay
//

import Foundation

/// Identity and on-disk locations for LibriVox books.
enum LibriVoxIdentity {
    static let scheme = "librivox"
    private static let host = "book"

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LibriVox", isDirectory: true)
    }

    // MARK: - Identity

    static func bookURL(id: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(id)"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    static func bookID(from url: URL?) -> String? {
        guard let url, url.scheme == scheme, url.host == host else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty || id == "/" ? nil : id
    }

    // MARK: - File locations

    /// `<root>/<id>/`, created on demand and excluded from backup.
    static func directory(forBookID id: String, root: URL = defaultRoot) throws -> URL {
        var directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }

    static func localFileURL(for chapter: ChapterModel, bookID: String, root: URL = defaultRoot) -> URL? {
        guard let remoteURL = chapter.remoteURL else { return nil }
        return root
            .appendingPathComponent(bookID, isDirectory: true)
            .appendingPathComponent(remoteURL.lastPathComponent)
    }

    static func isDownloaded(_ chapter: ChapterModel, bookID: String, root: URL = defaultRoot) -> Bool {
        guard let local = localFileURL(for: chapter, bookID: bookID, root: root) else { return false }
        return FileManager.default.fileExists(atPath: local.path)
    }

    /// Whether the "Downloaded" tag applies: a tracked download is complete, or nothing is tracked
    /// and every chapter's file is on disk.
    static func isFullyDownloaded(_ book: AudioModel, state: BookDownloadState?, root: URL = defaultRoot) -> Bool {
        guard let id = book.librivoxID else { return false }
        if let state { return state.isComplete }
        return !book.chapters.isEmpty && book.chapters.allSatisfy { isDownloaded($0, bookID: id, root: root) }
    }

    /// Local file if it exists, else the remote URL (streaming).
    static func playableURL(for chapter: ChapterModel, bookID: String, root: URL = defaultRoot) -> URL? {
        if isDownloaded(chapter, bookID: bookID, root: root),
           let local = localFileURL(for: chapter, bookID: bookID, root: root) {
            return local
        }
        return chapter.remoteURL
    }
}

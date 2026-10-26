//
//  ReimportMatcher.swift
//  Abbay
//

import Foundation

/// Finds the library book a newly picked file already is, so importing a moved file again from its
/// new place relinks that book instead of adding a second one (#196).
///
/// A picked file's URL is a new identity whenever the file moved, so `FileLoader`'s lookup by URL
/// misses it. Two ways it is still the same book:
/// 1. **The same file:** a stored book's `fileURL` (where its bookmark resolves now) is the picked
///    file: the same path once symlinks are resolved, or the same file resource identifier (a hard
///    link, or a path spelled differently).
/// 2. **A lost book's file:** the moved-file notice asks the user to import a book again when its
///    bookmark no longer finds the file. Nothing then points at the new place, so the match is by
///    what the book was: an imported (not LibriVox) book whose file isn't reachable, with the same
///    duration (to the second) and the same file name or the same non-empty title. Only when exactly
///    one book fits: a guess between two would relink the wrong one.
struct ReimportMatcher {
    /// Whether two file URLs are the same file.
    var isSameFile: (URL, URL) -> Bool = ReimportMatcher.isSameFile
    /// Whether a stored book's file is there.
    var isReachable: (URL) -> Bool = { (try? $0.checkResourceIsReachable()) == true }

    /// How far apart two durations may be and still be one file's, in seconds.
    static let durationTolerance: Double = 1

    /// The book in `library` that `imported` (just loaded from the picked file) already is, if any.
    func existingBook(for imported: AudioModel, in library: [AudioModel]) -> AudioModel? {
        guard let picked = imported.url else { return nil }
        let files = library.filter { !$0.isLibriVox && $0.url != nil }
        if let same = files.first(where: { $0.fileURL.map { isSameFile($0, picked) } == true }) {
            return same
        }
        let lost = files.filter { book in
            guard let fileURL = book.fileURL, !isReachable(fileURL) else { return false }
            return Self.looksLike(book, imported)
        }
        return lost.count == 1 ? lost.first : nil
    }

    /// `book` relinked to the picked file: its identity, position and fields, with the new
    /// bookmark, opening the file where it is now.
    static func relink(_ book: AudioModel, to imported: AudioModel) -> AudioModel {
        var relinked = book
        relinked.bookmarkData = imported.bookmarkData ?? book.bookmarkData
        relinked.resolvedURL = imported.url == book.url ? nil : imported.url
        return relinked
    }

    private static func looksLike(_ book: AudioModel, _ imported: AudioModel) -> Bool {
        guard book.duration > 0, abs(book.duration - imported.duration) <= durationTolerance else { return false }
        let sameName = book.url?.lastPathComponent == imported.url?.lastPathComponent
        let sameTitle = !book.title.isEmpty && book.title == imported.title
        return sameName || sameTitle
    }

    /// The same path once standardized and symlinks resolved (`/private/var` and `/var`), or the
    /// same file resource identifier. Reading the identifier of a file in another app's container
    /// needs its security scope, so each URL's is opened for the read.
    static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        guard lhs.isFileURL, rhs.isFileURL else { return false }
        if canonicalPath(lhs) == canonicalPath(rhs) { return true }
        guard let left = resourceIdentifier(of: lhs), let right = resourceIdentifier(of: rhs) else { return false }
        return left.isEqual(right)
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func resourceIdentifier(of url: URL) -> NSObject? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject
    }
}

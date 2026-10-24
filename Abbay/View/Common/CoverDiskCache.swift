//
//  CoverDiskCache.swift
//  Abbay
//

import CryptoKit
import Foundation

/// Cover image bytes on disk, one file per URL, so a cover loaded once doesn't download again after
/// a relaunch. `AsyncImageLoader` keeps decoded images in memory in front of it.
///
/// Like `CatalogCache` it lives in Caches, so the system may purge it and it is never backed up,
/// and every failure to read or write is ignored: the cache only saves time. It is bounded by
/// `byteLimit`: after each write the least recently used files (by modification date, which a read
/// refreshes) go until the rest fit. File names are a SHA-256 of the URL, so no title or
/// identifier is readable from the directory.
final class CoverDiskCache {
    enum Policy {
        /// A LibriVox cover from archive.org's image service is typically 10-60 KB, so this holds
        /// several hundred: every Popular card, a few searches and the books opened from them.
        static let byteLimit = 30 * 1024 * 1024
    }

    static let shared = CoverDiskCache(directory: defaultDirectory)

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LibriVoxCovers", isDirectory: true)
    }

    let directory: URL
    private let byteLimit: Int
    private let now: () -> Date
    private let lock = NSLock()
    private let fileManager = FileManager.default

    init(directory: URL, byteLimit: Int = Policy.byteLimit, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.byteLimit = byteLimit
        self.now = now
    }

    /// The stored bytes for `url`, marking them as recently used; nil when there are none.
    func data(for url: URL) -> Data? {
        lock.withLock {
            let file = fileURL(for: url)
            guard let data = try? Data(contentsOf: file) else { return nil }
            try? fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
            return data
        }
    }

    /// Stores `data` for `url`, then trims the cache back under its byte limit.
    func store(_ data: Data, for url: URL) {
        lock.withLock {
            let file = fileURL(for: url)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard (try? data.write(to: file, options: .atomic)) != nil else { return }
            try? fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: file.path)
            trim()
        }
    }

    func remove(for url: URL) {
        lock.withLock {
            try? fileManager.removeItem(at: fileURL(for: url))
        }
    }

    func removeAll() {
        lock.withLock {
            try? fileManager.removeItem(at: directory)
        }
    }

    // MARK: - Private

    /// Drops the least recently used files until the rest fit in `byteLimit`. Call with `lock` held.
    private func trim() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        else { return }
        var entries = files.compactMap { file -> Entry? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            let lastUsed = values.contentModificationDate ?? .distantPast
            return Entry(file: file, lastUsed: lastUsed, size: values.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > byteLimit else { return }
        entries.sort { $0.lastUsed < $1.lastUsed }
        for entry in entries where total > byteLimit {
            try? fileManager.removeItem(at: entry.file)
            total -= entry.size
        }
    }

    private struct Entry {
        let file: URL
        let lastUsed: Date
        let size: Int
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }
}

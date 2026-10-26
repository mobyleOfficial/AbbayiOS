//
//  DownloadHousekeeping.swift
//  Abbay
//

import Foundation

/// The Settings screen's downloads section: how much space LibriVox downloads take, and which
/// books "Delete finished downloads" removes.
enum DownloadHousekeeping {
    /// How close to the end a saved position counts as finished. LibriVox metadata durations and
    /// the real files differ by a few seconds, and the last seconds are a spoken credit.
    static let endTolerance: Double = 30

    /// Whether the book has been listened to the end.
    static func isFinished(_ book: AudioModel) -> Bool {
        book.duration > 0 && book.currentTime >= book.duration - endTolerance
    }

    /// LibriVox books that are both fully downloaded and listened to the end. Imported files are
    /// never selected: Abbay doesn't own them.
    static func finishedDownloads(
        in books: [AudioModel],
        state: (String) -> BookDownloadState?,
        root: URL = LibriVoxIdentity.defaultRoot
    ) -> [AudioModel] {
        books.filter { book in
            guard let id = book.librivoxID, isFinished(book) else { return false }
            return LibriVoxIdentity.isFullyDownloaded(book, state: state(id), root: root)
        }
    }

    /// Bytes of every file under `root` (the LibriVox downloads directory). Zero when it doesn't
    /// exist yet. Walks the disk: call it off the main thread.
    static func bytesUsed(under root: URL = LibriVoxIdentity.defaultRoot, fileManager: FileManager = .default) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

//
//  ReadAlongStore.swift
//  Abbay
//

import CryptoKit
import Foundation

/// Read-along transcripts on disk, one JSON file per book, so what the device has already
/// transcribed survives a relaunch and is never done twice.
///
/// Files are named after a SHA-256 of the book's identity (`AudioModel.url`, which doesn't change
/// when a file moves, #186), so no title is readable from the directory. The root lives in
/// Application Support and is excluded from backup: a transcript is derived from audio the device
/// already holds, so restoring one would only carry text for a book that may not come back.
///
/// Every failure to read or write is swallowed: a missing transcript just means the player
/// transcribes again. All access goes through one serial queue, so the transcriber, the player and
/// Settings can touch it from any thread.
final class ReadAlongStore {
    static let shared = ReadAlongStore(root: defaultRoot)

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ReadAlong", isDirectory: true)
    }

    private let root: URL
    private let queue = DispatchQueue(label: "abbay.readalong.store")
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root
    }

    /// The book's transcript; nil when there is none, or when the file can't be decoded (then it
    /// is deleted, so a bad file doesn't linger).
    func load(bookURL: URL) -> ReadAlongTranscript? {
        queue.sync {
            let file = fileURL(for: bookURL)
            guard let data = try? Data(contentsOf: file) else { return nil }
            guard let transcript = try? JSONDecoder().decode(ReadAlongTranscript.self, from: data) else {
                try? fileManager.removeItem(at: file)
                return nil
            }
            return transcript
        }
    }

    /// Replaces the book's transcript. The root is made (and marked as not backed up) here, on the
    /// first save, so a user who never turns the feature on never gets the folder.
    func save(_ transcript: ReadAlongTranscript, bookURL: URL) {
        queue.sync {
            guard let data = try? JSONEncoder().encode(transcript) else { return }
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            excludeRootFromBackup()
            try? data.write(to: fileURL(for: bookURL), options: .atomic)
        }
    }

    /// The book left the library.
    func delete(bookURL: URL) {
        queue.sync {
            try? fileManager.removeItem(at: fileURL(for: bookURL))
        }
    }

    /// Read-along was turned off: nothing it made stays behind.
    func deleteAll() {
        queue.sync {
            try? fileManager.removeItem(at: root)
        }
    }

    // MARK: - Private

    private func fileURL(for bookURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(bookURL.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(name + ".json")
    }

    /// Call with the root in place; set again on every save, because `deleteAll` removes the folder.
    private func excludeRootFromBackup() {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = root
        try? folder.setResourceValues(values)
    }
}

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
/// Settings can touch it from any thread; saves are queued without waiting, everything else waits
/// its turn.
final class ReadAlongStore {
    /// The one store the app uses: the player's sessions, the off switch (`LiveSettingsEffects`) and
    /// deleting a book all go through it, so they always agree. Under `-seedReadAlong` it is a
    /// temporary one emptied at launch, so canned text never lands among the user's transcripts and
    /// each UI-test launch starts with none.
    static let shared = DebugOverrides.readAlongStore() ?? ReadAlongStore(root: defaultRoot)

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ReadAlong", isDirectory: true)
    }

    let root: URL
    private let queue = DispatchQueue(label: "abbay.readalong.store")
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root
    }

    /// A transcript read for a session, and the stamp its saves carry. A book deleted since the
    /// stamp was taken doesn't get its text back from a session still showing it (the iPad's split
    /// pane keeps the player up while the library deletes the book).
    struct Loaded {
        let transcript: ReadAlongTranscript?
        let stamp: Int
    }

    /// How often each book's file was deleted, by file name. Read and written on `queue` only.
    private var deletions: [String: Int] = [:]

    /// The book's transcript; nil when there is none, or when the file can't be decoded (then it
    /// is deleted, so a bad file doesn't linger). Blocks until the queue reaches it, so it waits
    /// for the saves already asked for.
    func load(bookURL: URL) -> ReadAlongTranscript? {
        queue.sync { read(bookURL: bookURL) }
    }

    /// `load`, off the caller's thread, with the stamp to save with: the session's way in, since a
    /// whole book's transcript takes a moment to decode and the main thread is drawing the text.
    func loadInBackground(bookURL: URL) async -> Loaded {
        await withCheckedContinuation { continuation in
            queue.async {
                let name = self.fileName(for: bookURL)
                continuation.resume(returning: Loaded(
                    transcript: self.read(bookURL: bookURL),
                    stamp: self.deletions[name, default: 0]
                ))
            }
        }
    }

    /// Replaces the book's transcript, on the store's queue: `save` returns at once, and encoding a
    /// whole book's text never holds up the main thread. The root is made (and marked as not backed
    /// up) here, on the first save, so a user who never turns the feature on never gets the folder.
    ///
    /// With a `stamp` from `loadInBackground`, the save is dropped if the book was deleted since.
    /// Saves and deletes run in the order they were asked for (the queue is serial), so a save asked
    /// for before `deleteAll` is removed by it, and the caller checks the setting before asking for
    /// one after.
    func save(_ transcript: ReadAlongTranscript, bookURL: URL, unlessDeletedSince stamp: Int? = nil) {
        queue.async {
            let name = self.fileName(for: bookURL)
            if let stamp, self.deletions[name, default: 0] != stamp { return }
            guard let data = try? JSONEncoder().encode(transcript) else { return }
            try? self.fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
            self.excludeRootFromBackup()
            try? data.write(to: self.root.appendingPathComponent(name), options: .atomic)
        }
    }

    /// Returns once every save asked for so far is on disk. For tests, which look at the files.
    func waitForPendingSaves() {
        queue.sync {}
    }

    /// The book left the library, or its text is starting over in another language. Saves stamped
    /// before this are dropped.
    func delete(bookURL: URL) {
        queue.sync {
            let name = fileName(for: bookURL)
            deletions[name, default: 0] += 1
            try? fileManager.removeItem(at: root.appendingPathComponent(name))
        }
    }

    /// Read-along was turned off: nothing it made stays behind.
    func deleteAll() {
        queue.sync {
            try? fileManager.removeItem(at: root)
        }
    }

    // MARK: - Private

    /// On `queue`.
    private func read(bookURL: URL) -> ReadAlongTranscript? {
        let file = root.appendingPathComponent(fileName(for: bookURL))
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard let transcript = try? JSONDecoder().decode(ReadAlongTranscript.self, from: data) else {
            try? fileManager.removeItem(at: file)
            return nil
        }
        return transcript
    }

    private func fileName(for bookURL: URL) -> String {
        let digest = SHA256.hash(data: Data(bookURL.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    /// Call with the root in place; set again on every save, because `deleteAll` removes the folder.
    private func excludeRootFromBackup() {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = root
        try? folder.setResourceValues(values)
    }
}

//
//  ReadAlongAudioSource.swift
//  Abbay
//

import Foundation

/// Where a book's audio is on the device, as files and the book time each one starts at.
///
/// The transcriber reads files, not the player's timeline, so it needs this to start from any book
/// time; the UI needs it to say the audio must be downloaded first. A LibriVox book is one file per
/// chapter, and a chapter that isn't downloaded yet is a segment with no file. An imported book is
/// one file, with any chapter markers inside it, so it is one segment covering the whole book.
///
/// Read-along only ever reads what is already here: a missing file is never fetched.
struct ReadAlongAudioSource: Equatable {
    struct Segment: Equatable {
        /// Nil when the file is not on the device.
        let fileURL: URL?
        /// The book time where this file's 0 s is.
        let bookStart: Double
        let duration: Double
        /// An imported file lives outside the sandbox: reads go between
        /// `startAccessingSecurityScopedResource` and `stopAccessingSecurityScopedResource`.
        let isSecurityScoped: Bool
    }

    let segments: [Segment]
    let isLibriVox: Bool

    /// `fileExists` is the only side effect, and the one tests replace.
    static func make(
        for book: AudioModel,
        root: URL = LibriVoxIdentity.defaultRoot,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> ReadAlongAudioSource {
        if let bookID = book.librivoxID {
            let segments = book.chapters.map { chapter in
                let local = LibriVoxIdentity.localFileURL(for: chapter, bookID: bookID, root: root)
                return Segment(
                    fileURL: local.flatMap { fileExists($0) ? $0 : nil },
                    bookStart: chapter.startTime,
                    duration: chapter.duration,
                    isSecurityScoped: false
                )
            }
            return ReadAlongAudioSource(segments: segments, isLibriVox: true)
        }
        let segment = Segment(
            fileURL: book.fileURL.flatMap { importedFileExists($0, fileExists) ? $0 : nil },
            bookStart: 0,
            duration: book.duration,
            isSecurityScoped: true
        )
        return ReadAlongAudioSource(segments: [segment], isLibriVox: false)
    }

    /// The segment that holds `bookTime`: the last one starting at or before it. Clamped, so a time
    /// before the first segment reads as the first and one past the end as the last. Nil without
    /// segments.
    func segment(at bookTime: Double) -> Segment? {
        segments.last { $0.bookStart <= bookTime } ?? segments.first
    }

    func isOnDevice(at bookTime: Double) -> Bool {
        segment(at: bookTime)?.fileURL != nil
    }

    /// An imported file outside the sandbox can't be seen without its security scope.
    private static func importedFileExists(_ url: URL, _ fileExists: (URL) -> Bool) -> Bool {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return fileExists(url)
    }
}

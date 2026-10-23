//
//  UITestLibriVoxClient.swift
//  Abbay
//

#if DEBUG
import Foundation

/// Answers LibriVox requests from memory, so UI tests that exercise the search never touch the
/// network. Enabled by `LaunchArgument.stubLibriVox`. Popular is empty and only a query containing
/// "stub" finds a book, so every other query still reaches the "no results" state.
struct UITestLibriVoxClient: LibriVoxClientProtocol {
    static let book = LibriVoxBook(
        id: "ui-test-stub",
        title: "Stub LibriVox Book",
        authors: "Stub Author",
        descriptionText: "A book that only exists in UI tests.",
        language: "English",
        totalSeconds: 60,
        archiveIdentifier: "ui-test-stub",
        coverURL: URL(fileURLWithPath: "/dev/null/cover.jpg"),
        // A file URL that doesn't exist: playing it must not reach the network.
        sections: [
            LibriVoxBook.Section(
                title: "Stub Chapter",
                seconds: 60,
                listenURL: URL(fileURLWithPath: "/dev/null/stub_chapter_01.mp3")
            )
        ]
    )

    func search(_ query: String) async throws -> [LibriVoxBook] {
        query.range(of: "stub", options: .caseInsensitive) == nil ? [] : [Self.book]
    }

    func popular() async throws -> [LibriVoxBook] { [] }

    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails {
        guard book.id == Self.book.id else { throw URLError(.unsupportedURL) }
        // Small, so Download never asks about cellular.
        return LibriVoxBookDetails(book: Self.book, sectionBytes: [1000])
    }

    func coverData(for book: LibriVoxBook) async -> Data? { nil }
}
#endif

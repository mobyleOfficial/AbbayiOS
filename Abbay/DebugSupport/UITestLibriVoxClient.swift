//
//  UITestLibriVoxClient.swift
//  Abbay
//

#if DEBUG
import Foundation

/// Answers LibriVox requests from memory, so UI tests that exercise the search never touch the
/// network. Enabled by `LaunchArgument.stubLibriVox`. Popular is the one book and only a query containing
/// "stub" finds a book, so every other query still reaches the "no results" state.
struct UITestLibriVoxClient: LibriVoxClientProtocol {
    static let book = LibriVoxBook(
        id: "ui-test-stub",
        title: "Stub LibriVox Book",
        authors: "Stub Author",
        descriptionText: "A book that only exists in UI tests.",
        language: "eng",
        totalSeconds: 60,
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

    func popular() async throws -> [LibriVoxBook] { [Self.book] }

    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails {
        guard book.id == Self.book.id else { throw URLError(.unsupportedURL) }
        return LibriVoxBookDetails(book: Self.book, sectionBytes: [Self.sectionBytes])
    }

    /// Under the 99 MB cellular threshold, so Download never asks about cellular, and with a
    /// decimal ("29.7 MB", "29,7 MB"), so the size shows which locale formatted it (#166).
    static let sectionBytes: Int64 = 29_670_000

    func coverData(for book: LibriVoxBook) async -> Data? { nil }
}
#endif

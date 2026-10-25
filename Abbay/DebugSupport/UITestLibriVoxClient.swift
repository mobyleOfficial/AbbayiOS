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
    /// A file URL, which the cover loader's host allowlist refuses, so the cover fails.
    static let failingCoverURL = URL(fileURLWithPath: "/dev/null/cover.jpg")

    let book: LibriVoxBook
    let sectionBytes: [Int64]

    /// `coverURL` replaces the failing default (`-stubCovers` passes `UITestCoverNetwork.coverURL`).
    /// `isLarge` (`-stubDownloadStates`) gives the book three chapters and `largeSectionBytes` each,
    /// over the cellular threshold, so Download asks on a metered path and *Wait for Wi-Fi* holds it.
    init(coverURL: URL? = nil, isLarge: Bool = false) {
        let titles = isLarge ? (1...3).map { "Stub Chapter \($0)" } : ["Stub Chapter"]
        let sections = titles.enumerated().map { index, title in
            LibriVoxBook.Section(
                title: title,
                seconds: 60,
                // A file URL that doesn't exist: playing it must not reach the network.
                listenURL: URL(fileURLWithPath: "/dev/null/stub_chapter_0\(index + 1).mp3")
            )
        }
        book = LibriVoxBook(
            id: "ui-test-stub",
            title: "Stub LibriVox Book",
            authors: "Stub Author",
            descriptionText: "A book that only exists in UI tests.",
            language: "eng",
            totalSeconds: 60 * Double(sections.count),
            coverURL: coverURL ?? Self.failingCoverURL,
            sections: sections
        )
        sectionBytes = [Int64](repeating: isLarge ? Self.largeSectionBytes : Self.sectionBytes, count: sections.count)
    }

    func search(_ query: String) async throws -> [LibriVoxBook] {
        query.range(of: "stub", options: .caseInsensitive) == nil ? [] : [book]
    }

    func popular() async throws -> [LibriVoxBook] { [book] }

    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails {
        guard book.id == self.book.id else { throw URLError(.unsupportedURL) }
        return LibriVoxBookDetails(book: self.book, sectionBytes: sectionBytes)
    }

    /// Under the 99 MB cellular threshold, so Download never asks about cellular, and with a
    /// decimal ("29.7 MB", "29,7 MB"), so the size shows which locale formatted it (#166).
    static let sectionBytes: Int64 = 29_670_000
    /// Three of these are 120 MB, over the 99 MB threshold.
    static let largeSectionBytes: Int64 = 40_000_000

    func coverData(for book: LibriVoxBook) async -> Data? { nil }
}
#endif

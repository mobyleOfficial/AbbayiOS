//
//  UITestLibriVoxClient.swift
//  Abbay
//

#if DEBUG
import Foundation

/// Answers every LibriVox request with an empty result, so UI tests that exercise the search
/// never touch the network. Enabled by `LaunchArgument.stubLibriVox`.
struct UITestLibriVoxClient: LibriVoxClientProtocol {
    func search(_ query: String) async throws -> [LibriVoxBook] { [] }
    func popular() async throws -> [LibriVoxBook] { [] }

    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails {
        throw URLError(.unsupportedURL)
    }

    func coverData(for book: LibriVoxBook) async -> Data? { nil }
}
#endif

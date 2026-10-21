//
//  LibriVoxClient.swift
//  Abbay
//

import Foundation
import NetworkProvider

protocol LibriVoxClientProtocol {
    func search(_ query: String) async throws -> [LibriVoxBook]
    func popular() async throws -> [LibriVoxBook]
    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails
    func coverData(for book: LibriVoxBook) async -> Data?
}

final class LibriVoxClient: LibriVoxClientProtocol {
    /// archive.org's most-downloaded LibriVox items, in display order.
    static let popularIDs = ["200", "119", "253", "314", "448", "753", "271", "816", "56", "1557", "59"]

    private static let leadingArticles = ["the ", "a ", "an "]

    private let network: NetworkProviderProtocol

    init(network: NetworkProviderProtocol = NetworkProvider()) {
        self.network = network
    }

    func search(_ query: String) async throws -> [LibriVoxBook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        async let byTitle = books(for: LibriVoxRequests.titlePrefix(Self.withoutLeadingArticle(trimmed)))
        async let byAuthor = books(for: LibriVoxRequests.author(trimmed))
        let (titleMatches, authorMatches) = try await (byTitle, byAuthor)

        var seen = Set<String>()
        return (titleMatches + authorMatches).filter { seen.insert($0.id).inserted }
    }

    func popular() async throws -> [LibriVoxBook] {
        let results = await withTaskGroup(of: (Int, Result<[LibriVoxBook], Error>).self) { group in
            for (index, id) in Self.popularIDs.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await self.books(for: LibriVoxRequests.book(id: id))))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected = [(Int, Result<[LibriVoxBook], Error>)]()
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        let books = results.flatMap { result -> [LibriVoxBook] in
            if case let .success(books) = result { return books }
            return []
        }
        if books.isEmpty, let failure = results.compactMap({ result -> Error? in
            if case let .failure(error) = result { return error }
            return nil
        }).first {
            throw failure
        }
        return books
    }

    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails {
        let request = LibriVoxRequests.archiveMetadata(identifier: book.archiveIdentifier)
        let response: NetworkResponse<ArchiveMetadataDTO> = try await network.makeRequest(request)
        guard (200..<300).contains(response.statusCode) else { throw NetworkError.httpStatus(response.statusCode) }

        var sizes = [String: Int64]()
        for file in response.content.files ?? [] {
            guard let name = file.name else { continue }
            sizes[name] = file.size.flatMap { Int64($0) } ?? 0
        }
        let sectionBytes = book.sections.map { sizes[$0.listenURL.lastPathComponent] ?? 0 }
        return LibriVoxBookDetails(book: book, sectionBytes: sectionBytes)
    }

    func coverData(for book: LibriVoxBook) async -> Data? {
        let request = LibriVoxRequests.cover(for: book.coverURL)
        guard let response: NetworkResponse<Data> = try? await network.makeRequest(request),
              (200..<300).contains(response.statusCode),
              !response.content.isEmpty
        else { return nil }
        return response.content
    }
}

private extension LibriVoxClient {
    /// LibriVox drops a leading "The/A/An" from stored titles, so a prefix match must too.
    static func withoutLeadingArticle(_ query: String) -> String {
        let lowered = query.lowercased()
        for article in leadingArticles where lowered.hasPrefix(article) {
            let rest = query.dropFirst(article.count).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
        }
        return query
    }

    /// A 404 means "no match" and arrives either as a decoding error carrying 404 or as a 404 response.
    func books(for request: NetworkRequest) async throws -> [LibriVoxBook] {
        let response: NetworkResponse<LibriVoxSearchResponseDTO>
        do {
            response = try await network.makeRequest(request)
        } catch NetworkError.decoding(_, 404) {
            return []
        }
        if response.statusCode == 404 { return [] }
        guard (200..<300).contains(response.statusCode) else { throw NetworkError.httpStatus(response.statusCode) }
        return (response.content.books ?? []).compactMap(LibriVoxBook.init(dto:))
    }
}

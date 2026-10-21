//
//  MockLibriVoxClient.swift
//  AbbayTests
//

@testable import Abbay
import Foundation

final class MockLibriVoxClient: LibriVoxClientProtocol {
    var searchResult: Result<[LibriVoxBook], Error> = .success([])
    var popularResult: Result<[LibriVoxBook], Error> = .success([])
    var detailsResult: Result<LibriVoxBookDetails, Error> = .failure(URLError(.unsupportedURL))
    var coverResult: Data?
    private(set) var detailsCalls = 0
    private(set) var searchQueries = [String]()
    private(set) var popularCalls = 0

    func search(_ query: String) async throws -> [LibriVoxBook] {
        searchQueries.append(query)
        return try searchResult.get()
    }

    func popular() async throws -> [LibriVoxBook] {
        popularCalls += 1
        return try popularResult.get()
    }

    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails {
        detailsCalls += 1
        return try detailsResult.get()
    }

    func coverData(for book: LibriVoxBook) async -> Data? {
        coverResult
    }
}

final class FakeNetworkPath: NetworkPathProviding {
    var isCellular = false
    var isOnline = true
}

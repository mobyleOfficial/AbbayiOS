//
//  MockLibriVoxClient.swift
//  AbbayTests
//

@testable import Abbay
import Combine
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

/// Setting `isOnline` or `hold` publishes it synchronously, like a path update arriving.
final class FakeNetworkPath: NetworkPathProviding {
    var isMetered = false
    var isOnline = true {
        didSet { onlineSubject.send(isOnline) }
    }

    var hold: NetworkHold? {
        didSet { holdSubject.send(hold) }
    }

    /// Shorthand for `hold == .lowDataMode`.
    var isLowDataMode: Bool {
        get { hold == .lowDataMode }
        set { hold = newValue ? .lowDataMode : nil }
    }

    private let onlineSubject = CurrentValueSubject<Bool, Never>(true)
    private let holdSubject = CurrentValueSubject<NetworkHold?, Never>(nil)

    var onlinePublisher: AnyPublisher<Bool, Never> {
        onlineSubject.eraseToAnyPublisher()
    }

    var holdPublisher: AnyPublisher<NetworkHold?, Never> {
        holdSubject.eraseToAnyPublisher()
    }
}

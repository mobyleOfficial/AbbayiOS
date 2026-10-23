//
//  LibriVoxClientTestCase.swift
//  AbbayTests
//

@testable import Abbay
import NetworkProvider
import XCTest

/// Shared setup for the `LibriVoxClient` suites: a throwaway cache directory, a settable clock and
/// a router that answers each endpoint from a fixture.
class LibriVoxClientTestCase: XCTestCase {
    typealias Reply = MockNetworkProvider.Reply

    let day: TimeInterval = 24 * 60 * 60
    var directory = FileManager.default.temporaryDirectory
    var now = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    var cache: CatalogCache {
        CatalogCache(directory: directory) { [unowned self] in now }
    }

    func makeSUT(
        _ handler: @escaping (NetworkRequestProtocol) throws -> Reply
    ) -> (LibriVoxClient, MockNetworkProvider) {
        let network = MockNetworkProvider(handler: handler)
        return (LibriVoxClient(network: network, cache: cache), network)
    }

    func fixture(_ name: String, status: Int = 200) throws -> Reply {
        Reply(statusCode: status, data: try TestFixtures.librivoxData(name))
    }

    func light(_ id: String) -> LibriVoxBook {
        .light(id: id)
    }

    /// Answers archive metadata, LibriVox feed and archive search from the given replies.
    func router(
        metadata: Reply? = nil,
        feed: ((NetworkRequestProtocol) throws -> Reply)? = nil,
        search: Reply? = nil
    ) -> (NetworkRequestProtocol) throws -> Reply {
        { request in
            if request.endpoint.hasPrefix(LibriVoxRequests.metadataEndpoint), let metadata { return metadata }
            if request.endpoint == LibriVoxRequests.feedEndpoint, let feed { return try feed(request) }
            if request.endpoint == LibriVoxRequests.archiveSearchEndpoint, let search { return search }
            throw URLError(.notConnectedToInternet)
        }
    }

    func feedRequests(_ network: MockNetworkProvider) -> [[String: String]] {
        network.requests.filter { $0.endpoint == LibriVoxRequests.feedEndpoint }.compactMap(\.queryParams)
    }

    /// A full page of LibriVox books, none of them the one being looked up.
    func unrelatedPage(size: Int = 100) -> Reply {
        let books = (0..<size).map {
            #"{"id":"\#($0)","url_iarchive":"https://www.archive.org/details/other_\#($0)","sections":[]}"#
        }
        return Reply(data: Data(#"{"books":[\#(books.joined(separator: ","))]}"#.utf8))
    }
}

extension LibriVoxBook {
    /// A light result, as search returns it.
    static func light(id: String, coverURL: URL = URL(fileURLWithPath: "/cover")) -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: id,
            authors: "",
            descriptionText: "",
            language: "",
            totalSeconds: 0,
            coverURL: coverURL,
            sections: []
        )
    }
}

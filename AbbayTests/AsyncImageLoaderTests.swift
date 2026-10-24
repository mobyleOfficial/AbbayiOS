//
//  AsyncImageLoaderTests.swift
//  AbbayTests
//

@testable import Abbay
import NetworkProvider
import UIKit
import XCTest

/// Covers load through `NetworkProviderProtocol`, keep loaded images in memory by URL, and report
/// any failure as `nil` without caching it.
final class AsyncImageLoaderTests: XCTestCase {
    private typealias Reply = MockNetworkProvider.Reply

    private let url = URL(string: "https://archive.org/services/img/alice_in_wonderland_librivox")

    // MARK: - Helpers

    private func makeSUT(
        handler: @escaping (NetworkRequestProtocol) throws -> Reply
    ) -> (AsyncImageLoader, MockNetworkProvider) {
        let network = MockNetworkProvider(handler: handler)
        return (AsyncImageLoader(network: network, cache: NSCache()), network)
    }

    private func png(side: CGFloat = 4) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    // MARK: - Load

    func test_image_requestsTheCoverURL_throughTheNetworkProvider() async throws {
        let url = try XCTUnwrap(url)
        let data = png()
        let (sut, network) = makeSUT { _ in Reply(data: data) }

        _ = await sut.image(for: url)

        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(network.requests.first?.endpoint, url.absoluteString)
        XCTAssertEqual(network.requests.first?.httpMethod, .get)
    }

    func test_image_decodesTheResponse() async throws {
        let url = try XCTUnwrap(url)
        let data = png(side: 4)
        let (sut, _) = makeSUT { _ in Reply(data: data) }

        let loaded = await sut.image(for: url)

        let image = try XCTUnwrap(loaded)

        XCTAssertEqual(image.size, CGSize(width: 4, height: 4))
    }

    // MARK: - Cache

    func test_cachedImage_isNil_beforeALoad() throws {
        let url = try XCTUnwrap(url)
        let (sut, _) = makeSUT { _ in XCTFail("no request expected"); return Reply(data: Data()) }

        XCTAssertNil(sut.cachedImage(for: url))
    }

    func test_cachedImage_returnsTheLoadedImage_withoutARequest() async throws {
        let url = try XCTUnwrap(url)
        let data = png()
        let (sut, network) = makeSUT { _ in Reply(data: data) }
        let loaded = await sut.image(for: url)

        let cached = sut.cachedImage(for: url)

        XCTAssertNotNil(cached)
        XCTAssertTrue(cached === loaded)
        XCTAssertEqual(network.requests.count, 1)
    }

    func test_image_secondLoad_isServedFromTheCache() async throws {
        let url = try XCTUnwrap(url)
        let data = png()
        let (sut, network) = makeSUT { _ in Reply(data: data) }

        let first = await sut.image(for: url)
        let second = await sut.image(for: url)

        XCTAssertNotNil(second)
        XCTAssertTrue(first === second)
        XCTAssertEqual(network.requests.count, 1)
    }

    func test_image_isCachedPerURL() async throws {
        let url = try XCTUnwrap(url)
        let other = try XCTUnwrap(URL(string: "https://archive.org/services/img/other"))
        let data = png()
        let (sut, network) = makeSUT { _ in Reply(data: data) }

        _ = await sut.image(for: url)
        _ = await sut.image(for: other)

        XCTAssertEqual(network.requests.map(\.endpoint), [url.absoluteString, other.absoluteString])
    }

    // MARK: - Failure

    func test_image_whenTheRequestFails_isNil_andNotCached() async throws {
        let url = try XCTUnwrap(url)
        let (sut, network) = makeSUT { _ in throw NetworkError.connection }

        let first = await sut.image(for: url)
        let second = await sut.image(for: url)

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertNil(sut.cachedImage(for: url))
        XCTAssertEqual(network.requests.count, 2)
    }

    func test_image_whenTheStatusIsNotSuccess_isNil() async throws {
        let url = try XCTUnwrap(url)
        let data = png()
        let (sut, _) = makeSUT { _ in Reply(statusCode: 404, data: data) }

        let image = await sut.image(for: url)

        XCTAssertNil(image)
        XCTAssertNil(sut.cachedImage(for: url))
    }

    func test_image_whenTheBodyIsNotAnImage_isNil() async throws {
        let url = try XCTUnwrap(url)
        let (sut, _) = makeSUT { _ in Reply(data: Data("<html>not found</html>".utf8)) }

        let image = await sut.image(for: url)

        XCTAssertNil(image)
        XCTAssertNil(sut.cachedImage(for: url))
    }

    func test_image_whenTheBodyIsEmpty_isNil() async throws {
        let url = try XCTUnwrap(url)
        let (sut, _) = makeSUT { _ in Reply(data: Data()) }

        let image = await sut.image(for: url)

        XCTAssertNil(image)
    }
}

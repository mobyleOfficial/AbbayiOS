//
//  AsyncImageLoaderTests.swift
//  AbbayTests
//

@testable import Abbay
import NetworkProvider
import UIKit
import XCTest

/// Covers load through `NetworkProviderProtocol` from allowlisted hosts only, keep loaded images
/// in memory and their bytes on disk by URL, share one download between concurrent loads of a URL,
/// and report any failure as `nil` without caching it.
final class AsyncImageLoaderTests: XCTestCase {
    private typealias Reply = MockNetworkProvider.Reply

    private let url = URL(string: "https://archive.org/services/img/alice_in_wonderland_librivox")
    private var directory = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Helpers

    /// A loader with its own memory cache over the test's disk directory, so two calls model two
    /// launches of the app.
    private func makeSUT(
        handler: @escaping (NetworkRequestProtocol) throws -> Reply
    ) -> (AsyncImageLoader, MockNetworkProvider) {
        let network = MockNetworkProvider(handler: handler)
        let disk = CoverDiskCache(directory: directory)
        return (AsyncImageLoader(network: network, cache: NSCache(), diskCache: disk), network)
    }

    private func noRequestExpected(_ request: NetworkRequestProtocol) throws -> Reply {
        XCTFail("no request expected, got \(request.endpoint)")
        return Reply(data: Data())
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

    // MARK: - Disk cache

    func test_image_afterARelaunch_isServedFromDisk_withoutARequest() async throws {
        let url = try XCTUnwrap(url)
        let data = png()
        let (firstLaunch, _) = makeSUT { _ in Reply(data: data) }
        _ = await firstLaunch.image(for: url)

        let (secondLaunch, network) = makeSUT(handler: noRequestExpected)
        let image = await secondLaunch.image(for: url)

        XCTAssertEqual(image?.size, CGSize(width: 4, height: 4))
        XCTAssertEqual(network.requests.count, 0)
    }

    func test_image_whenOnDisk_isServedFromDisk_withoutARequest() async throws {
        let url = try XCTUnwrap(url)
        CoverDiskCache(directory: directory).store(png(side: 6), for: url)
        let (sut, network) = makeSUT(handler: noRequestExpected)

        let image = await sut.image(for: url)

        XCTAssertEqual(image?.size, CGSize(width: 6, height: 6))
        XCTAssertEqual(network.requests.count, 0)
    }

    func test_image_fromDisk_isThenKeptInMemory() async throws {
        let url = try XCTUnwrap(url)
        CoverDiskCache(directory: directory).store(png(), for: url)
        let (sut, _) = makeSUT(handler: noRequestExpected)

        let loaded = await sut.image(for: url)

        XCTAssertNotNil(loaded)
        XCTAssertTrue(sut.cachedImage(for: url) === loaded)
    }

    func test_image_whenTheDiskEntryIsNotAnImage_downloadsAndReplacesIt() async throws {
        let url = try XCTUnwrap(url)
        let disk = CoverDiskCache(directory: directory)
        disk.store(Data("corrupt".utf8), for: url)
        let data = png()
        let (sut, network) = makeSUT { _ in Reply(data: data) }

        let image = await sut.image(for: url)

        XCTAssertNotNil(image)
        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(disk.data(for: url), data)
    }

    func test_image_whenTheLoadFails_writesNothingToDisk() async throws {
        let url = try XCTUnwrap(url)
        let (sut, _) = makeSUT { _ in Reply(statusCode: 500, data: Data("<html>oops</html>".utf8)) }

        _ = await sut.image(for: url)

        XCTAssertNil(CoverDiskCache(directory: directory).data(for: url))
    }

    // MARK: - Shared in-flight requests

    func test_image_concurrentLoadsOfOneURL_shareOneRequest() async throws {
        let url = try XCTUnwrap(url)
        let data = png()
        let gate = Gate()
        let (sut, network) = makeSUT { _ in Reply(data: data) }
        network.beforeReply = { await gate.wait() }

        async let first = sut.image(for: url)
        async let second = sut.image(for: url)
        // Both loads are running before the one download is let through: without sharing, the
        // second would have reached the network by then too.
        try await waitUntil { network.requests.count >= 1 }
        try await Task.sleep(for: .milliseconds(200))
        await gate.open()
        let images = await [first, second]

        XCTAssertEqual(network.requests.count, 1)
        XCTAssertNotNil(images[0])
        XCTAssertTrue(images[0] === images[1])
    }

    func test_image_concurrentLoadsOfDifferentURLs_eachRequest() async throws {
        let url = try XCTUnwrap(url)
        let other = try XCTUnwrap(URL(string: "https://archive.org/services/img/other"))
        let data = png()
        let gate = Gate()
        let (sut, network) = makeSUT { _ in Reply(data: data) }
        network.beforeReply = { await gate.wait() }

        async let first = sut.image(for: url)
        async let second = sut.image(for: other)
        try await waitUntil { network.requests.count >= 2 }
        await gate.open()
        _ = await [first, second]

        XCTAssertEqual(Set(network.requests.map(\.endpoint)), [url.absoluteString, other.absoluteString])
    }

    func test_image_afterASharedLoadFails_theNextLoadRequestsAgain() async throws {
        let url = try XCTUnwrap(url)
        let (sut, network) = makeSUT { _ in throw NetworkError.connection }

        _ = await sut.image(for: url)
        _ = await sut.image(for: url)

        XCTAssertEqual(network.requests.count, 2)
    }

    // MARK: - Host allowlist

    func test_image_fromADisallowedHost_isNil_withoutARequest() async throws {
        let refused = [
            "https://example.com/cover.jpg",
            "https://archive.org.example.com/cover.jpg",
            "https://notarchive.org/cover.jpg",
            "https://librivox.org.evil.net/cover.jpg",
            "http://archive.org/services/img/alice",
            "file:///dev/null/cover.jpg"
        ]
        let (sut, network) = makeSUT(handler: noRequestExpected)

        for string in refused {
            let url = try XCTUnwrap(URL(string: string))
            let image = await sut.image(for: url)
            XCTAssertNil(image, string)
            XCTAssertNil(sut.cachedImage(for: url), string)
        }

        XCTAssertEqual(network.requests.count, 0)
    }

    func test_image_fromADisallowedHost_isNotServedFromDisk() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/cover.jpg"))
        CoverDiskCache(directory: directory).store(png(), for: url)
        let (sut, _) = makeSUT(handler: noRequestExpected)

        let image = await sut.image(for: url)

        XCTAssertNil(image)
    }

    func test_image_fromAllowedHostsAndTheirSubdomains_isRequested() async throws {
        let allowed = [
            "https://archive.org/services/img/alice",
            "https://ia800300.us.archive.org/1/items/alice/cover.jpg",
            "https://librivox.org/images/cover.jpg",
            "https://www.librivox.org/images/cover.jpg",
            "https://ARCHIVE.ORG/services/img/upper"
        ]
        let data = png()
        let (sut, network) = makeSUT { _ in Reply(data: data) }

        for string in allowed {
            let image = await sut.image(for: try XCTUnwrap(URL(string: string)))
            XCTAssertNotNil(image, string)
        }

        XCTAssertEqual(network.requests.map(\.endpoint), allowed)
    }

    func test_hostPolicy_allowsOnlyHTTPSOnLibriVoxAndArchiveHosts() throws {
        let policy = CoverHostPolicy.libriVox

        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://archive.org/x"))))
        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://a.b.archive.org/x"))))
        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://librivox.org/x"))))
        XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "https://xarchive.org/x"))))
        XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "https://archive.org.evil.com/x"))))
        XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "http://archive.org/x"))))
        XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "file:///dev/null/cover.jpg"))))
    }

    // MARK: - Waiting

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("condition not met within \(timeout)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Holds every waiter until `open()`, then lets them (and any later waiter) through.
private actor Gate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

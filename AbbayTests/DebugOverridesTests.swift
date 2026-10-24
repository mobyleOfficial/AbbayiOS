//
//  DebugOverridesTests.swift
//  AbbayTests
//

#if DEBUG
@testable import Abbay
import XCTest

/// `-forceReduceMotion` is how the UI tests get Reduce Motion: `nil` must mean "follow the
/// system", so a normal launch never overrides the user's setting.
final class DebugOverridesTests: XCTestCase {
    func test_reduceMotion_withoutTheArgument_followsTheSystem() {
        XCTAssertNil(DebugOverrides.reduceMotion(arguments: ["/path/to/Abbay", LaunchArgument.seedLibrary]))
    }

    func test_reduceMotion_withTheArgument_isForcedOn() {
        XCTAssertEqual(DebugOverrides.reduceMotion(arguments: [LaunchArgument.forceReduceMotion]), true)
    }

    // MARK: - Stub covers

    func test_coverLoader_withoutTheArgument_isTheRealOne() {
        XCTAssertNil(DebugOverrides.coverLoader(arguments: [LaunchArgument.stubLibriVox]))
    }

    func test_stubBook_withoutStubCovers_hasACoverTheAllowlistRefuses() async throws {
        let client = try XCTUnwrap(DebugOverrides.libriVoxClient(arguments: [LaunchArgument.stubLibriVox]))
        let books = try await client.popular()
        let book = try XCTUnwrap(books.first)

        XCTAssertFalse(CoverHostPolicy.libriVox.allows(book.coverURL))
    }

    func test_stubBook_withStubCovers_hasTheStubNetworksAllowedCover() async throws {
        let arguments = [LaunchArgument.stubLibriVox, LaunchArgument.stubCovers]
        let client = try XCTUnwrap(DebugOverrides.libriVoxClient(arguments: arguments))
        let books = try await client.popular()
        let book = try XCTUnwrap(books.first)

        XCTAssertEqual(book.coverURL, UITestCoverNetwork.coverURL)
        XCTAssertTrue(CoverHostPolicy.libriVox.allows(book.coverURL))
    }

    func test_stubCoverNetwork_answersWithAnImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = CoverDiskCache(directory: directory)
        addTeardownBlock { disk.removeAll() }
        let network = UITestCoverNetwork(isOffline: false, delay: .zero)
        let loader = AsyncImageLoader(network: network, cache: NSCache(), diskCache: disk)

        let image = await loader.image(for: UITestCoverNetwork.coverURL)

        XCTAssertNotNil(image)
    }

    func test_stubCoversOffline_servesOnlyWhatAnEarlierLaunchStored() async throws {
        addTeardownBlock { CoverDiskCache(directory: UITestCoverNetwork.diskDirectory).removeAll() }
        let url = UITestCoverNetwork.coverURL
        let offlineArguments = [LaunchArgument.stubCovers, LaunchArgument.stubCoversOffline]
        // An earlier `-stubCovers` launch, without its 12 s wait.
        _ = DebugOverrides.coverLoader(arguments: [LaunchArgument.stubCovers])
        let online = AsyncImageLoader(
            network: UITestCoverNetwork(isOffline: false, delay: .zero),
            cache: NSCache(),
            diskCache: CoverDiskCache(directory: UITestCoverNetwork.diskDirectory)
        )
        _ = await online.image(for: url)

        let offline = try XCTUnwrap(DebugOverrides.coverLoader(arguments: offlineArguments))
        let fromDisk = await offline.image(for: url)
        // A fresh `-stubCovers` launch empties the disk cache, so offline then has nothing.
        _ = DebugOverrides.coverLoader(arguments: [LaunchArgument.stubCovers])
        let offlineAfterReset = try XCTUnwrap(DebugOverrides.coverLoader(arguments: offlineArguments))
        let afterReset = await offlineAfterReset.image(for: url)

        XCTAssertNotNil(fromDisk)
        XCTAssertNil(afterReset)
    }
}
#endif

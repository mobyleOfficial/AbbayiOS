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

    // MARK: - Siri authorization

    /// #163: a UI test's launch doesn't raise the Siri authorization alert, which raced the first
    /// tap on a fresh simulator; a normal launch still asks.
    func test_siriPrompt_isSkippedForAnyLaunchArgument() {
        for argument in LaunchArgument.all {
            let arguments = ["/path/to/Abbay", argument]
            XCTAssertTrue(DebugOverrides.skipsSiriAuthorizationPrompt(arguments: arguments), argument)
        }
    }

    func test_siriPrompt_isAskedOnANormalLaunch() {
        XCTAssertFalse(DebugOverrides.skipsSiriAuthorizationPrompt(arguments: ["/path/to/Abbay"]))
    }

    // MARK: - Import (#196)

    /// `-stubMovedImport` imports *Seeded Missing Book*'s file name from a new place, and the file is
    /// there to load: a copy of the fixture, so it isn't the same file as the linked seeds.
    func test_stubMovedImport_importsTheMissingBooksFileFromItsNewPlace() throws {
        let arguments = ["/path/to/Abbay", LaunchArgument.stubMovedImport]
        let urls = try XCTUnwrap(DebugOverrides.importURLs(arguments: arguments))
        let url = try XCTUnwrap(urls.first)
        let seed = try XCTUnwrap(UITestSeeder.missingFileModel().url)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(url.lastPathComponent, seed.lastPathComponent)
        XCTAssertNotEqual(url, seed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_launchArgumentAll_listsEveryArgumentOnce() {
        XCTAssertEqual(Set(LaunchArgument.all).count, LaunchArgument.all.count)
        XCTAssertEqual(LaunchArgument.all.count, 23, "a new launch argument belongs in `all`")
    }

    // MARK: - Stub download states and network path (#171)

    func test_networkPath_withoutAnArgument_isTheRealOne() {
        XCTAssertNil(DebugOverrides.networkPath(arguments: [LaunchArgument.stubLibriVox]))
    }

    func test_networkPath_followsTheArgument() throws {
        let cellular = try XCTUnwrap(DebugOverrides.networkPath(arguments: [LaunchArgument.stubPathCellular]))
        let hotspot = try XCTUnwrap(DebugOverrides.networkPath(arguments: [LaunchArgument.stubPathHotspot]))
        let lowData = try XCTUnwrap(DebugOverrides.networkPath(arguments: [LaunchArgument.stubPathLowDataMode]))

        XCTAssertEqual((cellular as? UITestNetworkPath)?.snapshot, UITestNetworkPath.cellular)
        XCTAssertEqual((hotspot as? UITestNetworkPath)?.snapshot, UITestNetworkPath.hotspot)
        XCTAssertEqual((lowData as? UITestNetworkPath)?.snapshot, UITestNetworkPath.lowDataMode)
        for path in [cellular, hotspot, lowData] {
            XCTAssertTrue(path.isOnline)
            XCTAssertTrue(path.isMetered, "Download must ask, so Wait for Wi-Fi can be chosen")
        }
    }

    func test_networkPath_offline_isNotOnline() throws {
        let offline = try XCTUnwrap(DebugOverrides.networkPath(arguments: [LaunchArgument.stubPathOffline]))

        XCTAssertEqual((offline as? UITestNetworkPath)?.snapshot, UITestNetworkPath.offline)
        XCTAssertFalse(offline.isOnline)
    }

    /// Popular and a "stub" search list the stub book first, then the extras, whose details load.
    func test_stubCatalog_listsTheStubBookFirst_thenExtrasWithDetails() async throws {
        let client = try XCTUnwrap(DebugOverrides.libriVoxClient(arguments: [LaunchArgument.stubLibriVox]))

        let popular = try await client.popular()
        let results = try await client.search("Stub")
        let none = try await client.search("zzzz")

        XCTAssertEqual(popular.first?.id, "ui-test-stub")
        XCTAssertGreaterThan(popular.count, 1)
        XCTAssertEqual(results.map(\.id), popular.map(\.id))
        XCTAssertTrue(none.isEmpty)
        let extra = try XCTUnwrap(popular.last)
        let details = try await client.details(for: extra)
        XCTAssertEqual(details.book.id, extra.id)
    }

    func test_stubBook_withStubDownloadStates_isOverTheCellularThreshold() async throws {
        let arguments = [LaunchArgument.stubLibriVox, LaunchArgument.stubDownloadStates]
        let client = try XCTUnwrap(DebugOverrides.libriVoxClient(arguments: arguments))
        let books = try await client.popular()
        let book = try XCTUnwrap(books.first)

        let details = try await client.details(for: book)

        XCTAssertEqual(details.book.sections.count, 3)
        XCTAssertGreaterThan(details.totalBytes, CellularDownloadPolicy.largeDownloadThreshold)
    }

    func test_stubDownloadManager_withoutStubDownloadStates_publishesNothing() throws {
        let manager = try XCTUnwrap(DebugOverrides.downloadManager(arguments: [LaunchArgument.stubLibriVox]))
        var received = [[String: BookDownloadState]]()
        let cancellable = manager.statesPublisher.sink { received.append($0) }

        manager.enqueue(stubAudio())

        XCTAssertTrue(received.allSatisfy(\.isEmpty))
        cancellable.cancel()
    }

    func test_stubDownloadManager_publishesAFixedStateThatPauseResumeAndRetryChange() throws {
        let arguments = [LaunchArgument.stubLibriVox, LaunchArgument.stubDownloadStates]
        let manager = try XCTUnwrap(DebugOverrides.downloadManager(arguments: arguments))
        var latest = [String: BookDownloadState]()
        let cancellable = manager.statesPublisher.sink { latest = $0 }

        manager.enqueue(stubAudio())
        XCTAssertEqual(latest["ui-test-stub"]?.chapters, [.downloaded, .waiting, .failed])
        XCTAssertEqual(latest["ui-test-stub"]?.isPaused, false)

        manager.pause(bookID: "ui-test-stub")
        XCTAssertEqual(latest["ui-test-stub"]?.isPaused, true)
        manager.resume(bookID: "ui-test-stub")
        manager.retry(chapterIndex: 2, ofBookID: "ui-test-stub")
        XCTAssertEqual(latest["ui-test-stub"]?.chapters, [.downloaded, .waiting, .waiting])
        XCTAssertEqual(latest["ui-test-stub"]?.isPaused, false)
        cancellable.cancel()
    }

    /// Three chapters, like the stub book with `-stubDownloadStates`.
    private func stubAudio() -> AudioModel {
        var book = ViewModelSupport.chaptered()
        book.librivoxID = "ui-test-stub"
        return book
    }
}
#endif

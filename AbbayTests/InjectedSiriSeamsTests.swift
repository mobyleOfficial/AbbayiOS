//
//  InjectedSiriSeamsTests.swift
//  AbbayTests
//

@testable import Abbay
import AppIntents
import Intents
import XCTest

/// #153: every Siri diagnostics write goes to an injected trail, so a unit test never writes the
/// real App Group; and the snapshot writer's publisher and the intents' audio session activator
/// are injected rather than rebound statics.
final class InjectedSiriSeamsTests: XCTestCase {
    private let appGroup = InMemoryKeyValueStore()
    private var trail: SiriDiagnostics { SiriDiagnostics(store: appGroup) }

    override func tearDownWithError() throws {
        DependencyContainer.reset()
        try super.tearDownWithError()
    }

    private func configureContainer(activator: AudioSessionActivatorProtocol = MockAudioSessionActivator()) {
        DependencyContainer.configure(with: MockDependencyContainer(
            player: MockPlayer(),
            loadAudio: MockLoadAudioUseCase(),
            loadAllAudios: MockLoadAllAudiosUseCase(),
            appGroup: appGroup,
            audioSessionActivator: activator
        ))
    }

    private func events(containing text: String) -> [String] {
        trail.events().filter { $0.contains(text) }
    }

    // MARK: - Diagnostics

    func test_intentRouter_recordsToItsInjectedTrail() {
        let router = IntentRouter(
            loadAudio: MockLoadAudioUseCase(),
            snapshotWriter: MockLibrarySnapshotWriter(),
            snapshotReader: { [] },
            player: { MockPlayer() },
            lastPlayed: .inMemory(),
            launchState: .inMemory(),
            diagnostics: trail
        )
        let item = INMediaItem(identifier: "file:///nowhere.m4b", title: "X", type: .audioBook, artwork: nil)

        _ = router.handle(INPlayMediaIntent(
            mediaItems: [item],
            mediaContainer: nil,
            playShuffled: nil,
            playbackRepeatMode: .none,
            resumePlayback: nil,
            playbackQueueLocation: .now,
            playbackSpeed: nil,
            mediaSearch: nil
        ))

        XCTAssertEqual(events(containing: "app handleInApp received").count, 1)
        XCTAssertEqual(events(containing: "app handleInApp load failed").count, 1)
    }

    func test_publisher_recordsToItsInjectedTrail() {
        let publisher = SiriLibraryPublisher(
            mediaUserContextDonor: NoopMediaUserContextDonor(),
            spotlightIndexer: NoopSpotlightIndexer(),
            vocabulary: { _ in },
            refreshShortcutParameters: {},
            lastPlayed: .inMemory(),
            diagnostics: trail
        )

        publisher.publish(audios: [AudioModel(title: "Dune", url: URL(string: "file:///dune"))])

        XCTAssertEqual(events(containing: "publish books=1").count, 1)
    }

    /// The system builds entity queries and App Intents itself: they record to the container's trail.
    func test_entityQuery_recordsToTheContainersTrail() async throws {
        configureContainer()

        _ = try await AudiobookEntityQuery().suggestedEntities()
        _ = try await ChapterEntityQuery().suggestedEntities()

        XCTAssertEqual(events(containing: "query book suggested").count, 1)
        XCTAssertEqual(events(containing: "query chapter suggested").count, 1)
    }

    func test_appIntent_recordsToTheContainersTrail() async throws {
        configureContainer()

        _ = try await PauseAbbayIntent().perform()

        XCTAssertEqual(events(containing: "appintent PauseAbbayIntent fired").count, 1)
    }

    // MARK: - Publisher

    func test_snapshotWriter_publishesThroughItsInjectedPublisher() {
        let publisher = CountingPublisher()
        let writer = LibrarySnapshotWriter(
            store: InMemoryKeyValueStore(),
            loadAllAudios: MockLoadAllAudiosUseCase(),
            publisher: publisher
        )

        writer.write(audios: [AudioModel(title: "Dune", url: URL(string: "file:///dune"))])

        XCTAssertEqual(publisher.publishedTitles, [["Dune"]])
    }

    // MARK: - Audio session

    func test_attemptActivation_usesTheContainersActivator() {
        let failing = MockAudioSessionActivator()
        failing.shouldThrow = true
        configureContainer(activator: failing)

        XCTAssertFalse(AudioSessionActivator.attemptActivation())
        XCTAssertTrue(DependencyContainer.launchState.isUnavailable())
    }
}

private final class CountingPublisher: SiriLibraryPublisherProtocol {
    private(set) var publishedTitles = [[String]]()

    func publish(audios: [AudioModel], completion: @escaping () -> Void) {
        publishedTitles.append(audios.map(\.title))
        completion()
    }
}

private struct NoopMediaUserContextDonor: MediaUserContextDonorProtocol {
    func donate(libraryItemCount: Int) {}
}

private struct NoopSpotlightIndexer: LibrarySpotlightIndexerProtocol {
    func index(audios: [AudioModel], completion: @escaping () -> Void) { completion() }
    func forgetIndexedItems(_ identifiers: [String]?) {}
}

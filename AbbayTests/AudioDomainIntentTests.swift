//
//  AudioDomainIntentTests.swift
//  AbbayTests
//

@testable import Abbay
import AppIntents
import XCTest
#if canImport(MediaIntents)
import MediaIntents
#endif

/// iOS 27's App Intents audio domain (#129): which books a Siri audio request finds, and what
/// `PlayAudioDomainIntent` does with one. The matching is a pure function, so it is checked on
/// every runtime; the schema types only exist on iOS 27, so those tests skip below it.
final class AudioDomainIntentTests: XCTestCase {
    private var player = MockPlayer()
    private var loader = MockLoadAudioUseCase()
    private var lister = MockLoadAllAudiosUseCase()
    private var appGroup = InMemoryKeyValueStore()
    private var container: MockDependencyContainer?

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        loader = MockLoadAudioUseCase()
        lister = MockLoadAllAudiosUseCase()
        appGroup = InMemoryKeyValueStore()
        let container = MockDependencyContainer(
            player: player,
            loadAudio: loader,
            loadAllAudios: lister,
            appGroup: appGroup
        )
        self.container = container
        DependencyContainer.configure(with: container)
    }

    override func tearDownWithError() throws {
        DependencyContainer.reset()
        container = nil
        try super.tearDownWithError()
    }

    private func book(_ title: String, _ url: String, artist: String = "", storedURL: String? = nil) -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.artist = artist
        model.url = URL(string: url)
        model.storedURL = storedURL.flatMap(URL.init(string:))
        return model
    }

    private var library: [AudioModel] {
        [
            book("Alice in Wonderland", "file:///alice"),
            book("Goblet of Fire", "file:///gof"),
            book("Moby Dick", "file:///moby")
        ]
    }

    // MARK: - AudioDomainMatcher (every runtime)

    func test_unspecified_putsTheLastPlayedBookFirst() throws {
        let books = AudioDomainMatcher.books(
            for: .unspecified,
            library: library,
            lastPlayedURL: URL(string: "file:///moby")
        )
        XCTAssertEqual(books.map(\.title), ["Moby Dick", "Alice in Wonderland", "Goblet of Fire"])
    }

    func test_unspecified_withNoLastPlayed_keepsLibraryOrder_andCaps() {
        let many = (0..<(AudiobookEntityQuery.suggestionLimit + 5)).map { book("Book \($0)", "file:///\($0)") }
        let books = AudioDomainMatcher.books(for: .unspecified, library: many, lastPlayedURL: nil)
        XCTAssertEqual(books.count, AudiobookEntityQuery.suggestionLimit)
        XCTAssertEqual(books.first?.title, "Book 0")
    }

    func test_query_usesTheFuzzyTitleRules() {
        let books = AudioDomainMatcher.books(for: .query("goblet of"), library: library, lastPlayedURL: nil)
        XCTAssertEqual(books.map(\.title), ["Goblet of Fire"])
    }

    func test_query_withNoMatch_isEmpty() {
        XCTAssertTrue(AudioDomainMatcher.books(for: .query("dune"), library: library, lastPlayedURL: nil).isEmpty)
    }

    func test_urls_matchTheBookURL_orTheURLItsRowIsSavedUnder() throws {
        let moved = book("Moved", "file:///new-place", storedURL: "file:///old-place")
        let books = AudioDomainMatcher.books(
            for: .urls([try XCTUnwrap(URL(string: "file:///gof")), try XCTUnwrap(URL(string: "file:///old-place"))]),
            library: library + [moved],
            lastPlayedURL: nil
        )
        XCTAssertEqual(books.map(\.title), ["Goblet of Fire", "Moved"])
    }

    func test_requestKind_neverCarriesWhatWasSaid() {
        XCTAssertEqual(AudioDomainRequest.query("secret title").kind, "query")
        XCTAssertEqual(AudioDomainRequest.unspecified.kind, "unspecified")
        XCTAssertEqual(AudioDomainRequest.urls([]).kind, "urls")
    }

    // MARK: - iOS 27 schema types

    #if canImport(MediaIntents)
    func test_audioSearchCriteria_mapOntoRequests() throws {
        guard #available(iOS 27, *) else { throw XCTSkip("the audio domain is iOS 27+") }
        let url = try XCTUnwrap(URL(string: "file:///gof"))
        XCTAssertEqual(AudioDomainBookQuery.request(for: .unspecified), .unspecified)
        XCTAssertEqual(AudioDomainBookQuery.request(for: .searchQuery("gof")), .query("gof"))
        XCTAssertEqual(AudioDomainBookQuery.request(for: .url([url])), .urls([url]))
    }

    func test_valueQuery_findsTheSpokenBook_andRecordsOnlyTheKind() async throws {
        guard #available(iOS 27, *) else { throw XCTSkip("the audio domain is iOS 27+") }
        lister.stub = library
        let found = try await AudioDomainBookQuery().values(
            for: AudioSearch(criteria: .searchQuery("goblet of fire"))
        )
        XCTAssertEqual(found.map(\.id), ["file:///gof"])
        XCTAssertEqual(found.first?.title, "Goblet of Fire")
        let trail = try XCTUnwrap(container?.diagnostics.events().last)
        XCTAssertTrue(trail.hasSuffix("query audio search query found=1"), trail)
        XCTAssertFalse(trail.contains("goblet"), "the trail must not hold what was said")
    }

    func test_entity_carriesTitleAndAuthor_andNoEmptyAuthor() throws {
        guard #available(iOS 27, *) else { throw XCTSkip("the audio domain is iOS 27+") }
        let withAuthor = try XCTUnwrap(AudioDomainBookEntity(model: book("Moby Dick", "file:///moby", artist: "Melville")))
        XCTAssertEqual(withAuthor.title, "Moby Dick")
        XCTAssertEqual(withAuthor.author, "Melville")
        XCTAssertNil(try XCTUnwrap(AudioDomainBookEntity(model: book("A", "file:///a"))).author)
        XCTAssertNil(AudioDomainBookEntity(model: AudioModel()), "a book without a URL can't be played")
    }

    @MainActor
    func test_playAudioIntent_playsTheBook() async throws {
        guard #available(iOS 27, *) else { throw XCTSkip("the audio domain is iOS 27+") }
        loader.stubs["file:///gof"] = book("Goblet of Fire", "file:///gof")
        let intent = PlayAudioDomainIntent()
        intent.audioEntity = .audiobook(AudioDomainBookEntity(id: "file:///gof", title: "Goblet of Fire", author: nil))
        _ = try await intent.perform()
        XCTAssertEqual(player.playCalls.map(\.title), ["Goblet of Fire"])
        XCTAssertTrue(container?.diagnostics.events().last?.hasSuffix("appintent PlayAudioDomainIntent fired") ?? false)
    }

    @MainActor
    func test_playAudioIntent_goneBook_doesNotPlay_andClearsItsLastPlayedPointer() async throws {
        guard #available(iOS 27, *) else { throw XCTSkip("the audio domain is iOS 27+") }
        let gone = try XCTUnwrap(URL(string: "file:///gone"))
        container?.lastPlayed.save(url: gone)
        let intent = PlayAudioDomainIntent()
        intent.audioEntity = .audiobook(AudioDomainBookEntity(id: gone.absoluteString, title: "Gone", author: nil))
        _ = try await intent.perform()
        XCTAssertTrue(player.playCalls.isEmpty)
        XCTAssertNil(container?.lastPlayed.lastPlayedURL())
    }

    func test_schemaEnums_areTranslatedToPortuguese() throws {
        guard #available(iOS 27, *) else { throw XCTSkip("the audio domain is iOS 27+") }
        let pairs: [(DisplayRepresentation?, String)] = [
            (AudioDomainPlaybackAttribute.caseDisplayRepresentations[.shuffle], "Aleatório"),
            (AudioDomainPlaybackAttribute.caseDisplayRepresentations[.repeat], "Repetir"),
            (AudioDomainQueueLocation.caseDisplayRepresentations[.next], "Tocar em seguida"),
            (AudioDomainQueueLocation.caseDisplayRepresentations[.tail], "Tocar por último")
        ]
        for (representation, portuguese) in pairs {
            XCTAssertEqual(try XCTUnwrap(representation).title.resolved(in: "pt-BR"), portuguese)
        }
    }
    #endif
}

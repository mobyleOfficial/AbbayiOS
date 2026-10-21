//
//  LibriVoxBookMappingTests.swift
//  AbbayTests
//

@testable import Abbay
import NetworkProvider
import XCTest

final class LibriVoxBookMappingTests: XCTestCase {
    private func aliceDetails() async throws -> LibriVoxBookDetails {
        let search = MockNetworkProvider.Reply(data: try TestFixtures.librivoxData("search_alice"))
        let metadata = MockNetworkProvider.Reply(data: try TestFixtures.librivoxData("archive_alice_metadata"))
        let client = LibriVoxClient(network: MockNetworkProvider { request in
            request.endpoint.contains("archive.org/metadata") ? metadata : search
        })
        let results = try await client.search("alice")
        let alice = try XCTUnwrap(results.first)
        return try await client.details(for: alice)
    }

    func test_audioModel_chaptersAreCumulative() async throws {
        let model = try await aliceDetails().audioModel(imageData: nil)

        XCTAssertEqual(model.chapters.count, 12)
        XCTAssertEqual(model.chapters[0].startTime, 0)
        XCTAssertEqual(model.chapters[0].duration, 640)
        XCTAssertEqual(model.chapters[1].startTime, 640)
        XCTAssertEqual(model.chapters[1].duration, 735)
        XCTAssertEqual(model.chapters[2].startTime, 1375)
    }

    func test_audioModel_identityAndMetadata() async throws {
        let details = try await aliceDetails()
        let cover = Data([9, 9])

        let model = details.audioModel(imageData: cover)

        XCTAssertEqual(model.url, URL(string: "librivox://book/200"))
        XCTAssertEqual(model.librivoxID, "200")
        XCTAssertEqual(model.title, "Alice's Adventures in Wonderland")
        XCTAssertEqual(model.albumName, "Alice's Adventures in Wonderland")
        XCTAssertEqual(model.artist, "Lewis Carroll")
        XCTAssertEqual(model.duration, details.book.totalSeconds)
        XCTAssertEqual(model.totalBytes, 85_862_932)
        XCTAssertEqual(model.imageData, cover)
    }

    func test_audioModel_chapterRemoteURLsAndBytes() async throws {
        let details = try await aliceDetails()

        let model = details.audioModel(imageData: nil)

        for (index, chapter) in model.chapters.enumerated() {
            XCTAssertEqual(chapter.remoteURL, details.book.sections[index].listenURL)
            XCTAssertEqual(chapter.expectedBytes, details.sectionBytes[index])
            XCTAssertEqual(chapter.title, details.book.sections[index].title)
        }
        XCTAssertEqual(
            model.chapters[0].remoteURL?.absoluteString,
            "https://www.archive.org/download/alice_in_wonderland_librivox/wonderland_ch_01_64kb.mp3"
        )
    }

    func test_description_stripsHTMLAndDecodesEntities() async throws {
        let details = try await aliceDetails()

        XCTAssertFalse(details.book.descriptionText.contains("<"))
        XCTAssertTrue(details.book.descriptionText.contains("(Summary written by Gesine)\n\n"))
    }

    func test_strippingHTML_handlesTagsAndEntities() {
        let html = "<p>Tom &amp; Jerry said &quot;hi&quot;, it&#39;s 1 &lt; 2 &gt; 0<br />Next<br/>line</p>"

        XCTAssertEqual(html.strippingHTML, "Tom & Jerry said \"hi\", it's 1 < 2 > 0\nNext\nline")
    }
}

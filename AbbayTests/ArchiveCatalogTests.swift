//
//  ArchiveCatalogTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class ArchiveCatalogTests: XCTestCase {
    private typealias File = ArchiveMetadataDTO.File

    private func mp3(_ name: String, track: String? = nil, title: String? = nil, length: String? = nil) -> File {
        File(name: name, format: "64Kbps MP3", size: "1", length: length, title: title, track: track)
    }

    // MARK: - Title

    func test_cleanTitle_dropsByCreatorSuffix() {
        XCTAssertEqual(
            ArchiveCatalog.cleanTitle("Alice's Adventures in Wonderland, by Lewis Carroll", creator: "Lewis Carroll"),
            "Alice's Adventures in Wonderland"
        )
    }

    func test_cleanTitle_suffixMatchIsCaseInsensitive() {
        XCTAssertEqual(ArchiveCatalog.cleanTitle("Emma, By JANE AUSTEN", creator: "Jane Austen"), "Emma")
    }

    func test_cleanTitle_keepsSuffixNamingSomeoneElse() {
        let title = "A Scandal in Bohemia, by Sir Arthur Conan Doyle"
        XCTAssertEqual(ArchiveCatalog.cleanTitle(title, creator: "Various"), title)
        XCTAssertEqual(ArchiveCatalog.cleanTitle(title, creator: nil), title)
    }

    func test_cleanTitle_neverEmpty() {
        XCTAssertEqual(ArchiveCatalog.cleanTitle(", by Homer", creator: "Homer"), ", by Homer")
        XCTAssertEqual(ArchiveCatalog.cleanTitle("  Dracula ", creator: "Bram Stoker"), "Dracula")
    }

    // MARK: - Length

    func test_seconds_minutesAndSeconds() {
        XCTAssertEqual(ArchiveCatalog.seconds(fromLength: "10:40"), 640)
        XCTAssertEqual(ArchiveCatalog.seconds(fromLength: "60:55"), 3655)
    }

    func test_seconds_hoursMinutesSeconds() {
        XCTAssertEqual(ArchiveCatalog.seconds(fromLength: "2:58:51"), 10_731)
    }

    func test_seconds_decimalSeconds() {
        XCTAssertEqual(ArchiveCatalog.seconds(fromLength: "640.52"), 640.52)
        XCTAssertEqual(ArchiveCatalog.seconds(fromLength: "95"), 95)
    }

    func test_seconds_unreadableIsNil() {
        XCTAssertNil(ArchiveCatalog.seconds(fromLength: nil))
        XCTAssertNil(ArchiveCatalog.seconds(fromLength: ""))
        XCTAssertNil(ArchiveCatalog.seconds(fromLength: "abc"))
        XCTAssertNil(ArchiveCatalog.seconds(fromLength: "1:xx"))
        XCTAssertNil(ArchiveCatalog.seconds(fromLength: "-5"))
    }

    // MARK: - Last name

    func test_lastName() {
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Lewis Carroll"), "Carroll")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Carroll, Lewis"), "Carroll")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Sir Arthur Conan Doyle"), "Doyle")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Homer"), "Homer")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Joaquim Maria Machado de Assis"), "Assis")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Sammy Davis Jr."), "Davis")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Martin Luther King, Jr."), "King")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Henry Ford II"), "Ford")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Oliver Wendell Holmes, Sr."), "Holmes")
        XCTAssertEqual(ArchiveCatalog.lastName(of: "Lewis Carroll,"), "Carroll")
        XCTAssertNil(ArchiveCatalog.lastName(of: ","))
        XCTAssertNil(ArchiveCatalog.lastName(of: nil))
        XCTAssertNil(ArchiveCatalog.lastName(of: "  "))
    }

    // MARK: - Fallback chapters

    func test_chapterFiles_ordersByNumericTrack() {
        let files = [
            mp3("c_64kb.mp3", track: "10/12"),
            mp3("a_64kb.mp3", track: "2/12"),
            mp3("b_64kb.mp3", track: "1")
        ]

        XCTAssertEqual(ArchiveCatalog.chapterFiles(files).map(\.name), ["b_64kb.mp3", "a_64kb.mp3", "c_64kb.mp3"])
    }

    func test_chapterFiles_withoutTrack_ordersByNameNumerically_afterTracked() {
        let files = [
            mp3("part_10_64kb.mp3"),
            mp3("part_2_64kb.mp3"),
            mp3("intro_64kb.mp3", track: "1")
        ]

        XCTAssertEqual(
            ArchiveCatalog.chapterFiles(files).map(\.name),
            ["intro_64kb.mp3", "part_2_64kb.mp3", "part_10_64kb.mp3"]
        )
    }

    func test_chapterFiles_keepsOnly64kbMP3() {
        let files = [
            File(name: "a.mp3", format: "VBR MP3", size: "1", length: nil, title: nil, track: "1"),
            File(name: "a.ogg", format: "Ogg Vorbis", size: "1", length: nil, title: nil, track: "1"),
            mp3("a_64kb.mp3", track: "1")
        ]

        XCTAssertEqual(ArchiveCatalog.chapterFiles(files).map(\.name), ["a_64kb.mp3"])
    }

    func test_fallbackSection_titleDurationAndURL() throws {
        let titled = try XCTUnwrap(ArchiveCatalog.fallbackSection(
            mp3("1891collection_02_64kb.mp3", title: "02 - A Scandal in Bohemia", length: "60:55"),
            identifier: "1891_collection_bt_librivox"
        ))
        let untitled = try XCTUnwrap(ArchiveCatalog.fallbackSection(
            mp3("part one_64kb.mp3", length: "12.5"),
            identifier: "some_item"
        ))

        XCTAssertEqual(titled.title, "02 - A Scandal in Bohemia")
        XCTAssertEqual(titled.seconds, 3655)
        XCTAssertEqual(
            titled.listenURL.absoluteString,
            "https://archive.org/download/1891_collection_bt_librivox/1891collection_02_64kb.mp3"
        )
        XCTAssertEqual(untitled.title, "part one_64kb")
        XCTAssertEqual(untitled.seconds, 12.5)
        XCTAssertEqual(untitled.listenURL.lastPathComponent, "part one_64kb.mp3")
        XCTAssertEqual(untitled.listenURL.absoluteString, "https://archive.org/download/some_item/part%20one_64kb.mp3")
    }
}

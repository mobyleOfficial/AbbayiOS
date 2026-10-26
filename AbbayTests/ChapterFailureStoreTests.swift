//
//  ChapterFailureStoreTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Failure counts are kept per chapter, by the book's id and the chapter's file name, in the
/// injected key-value store, so they outlive the process (#148).
final class ChapterFailureStoreTests: XCTestCase {
    private let values = InMemoryKeyValueStore()
    private lazy var sut = ChapterFailureStore(store: values)

    func test_unknownChapter_hasNoFailures() {
        XCTAssertEqual(sut.failures(bookID: "1", chapter: chapter("a.mp3")), 0)
    }

    func test_set_isReadBackByANewStoreOnTheSameValues() {
        sut.set(3, bookID: "1", chapter: chapter("a.mp3"))

        let relaunched = ChapterFailureStore(store: values)

        XCTAssertEqual(relaunched.failures(bookID: "1", chapter: chapter("a.mp3")), 3)
        XCTAssertEqual(relaunched.failures(bookID: "1", chapter: chapter("b.mp3")), 0)
        XCTAssertEqual(relaunched.failures(bookID: "2", chapter: chapter("a.mp3")), 0)
    }

    func test_setZero_forgetsTheChapter() {
        sut.set(2, bookID: "1", chapter: chapter("a.mp3"))

        sut.set(0, bookID: "1", chapter: chapter("a.mp3"))

        XCTAssertEqual(sut.failures(bookID: "1", chapter: chapter("a.mp3")), 0)
        XCTAssertNil(values.object(forKey: ChapterFailureStore.key), "Nothing left: the key is removed")
    }

    func test_removeAll_forgetsOnlyThatBook() {
        sut.set(2, bookID: "1", chapter: chapter("a.mp3"))
        sut.set(1, bookID: "1", chapter: chapter("b.mp3"))
        sut.set(4, bookID: "12", chapter: chapter("a.mp3"))

        sut.removeAll(bookID: "1")

        XCTAssertEqual(sut.failures(bookID: "1", chapter: chapter("a.mp3")), 0)
        XCTAssertEqual(sut.failures(bookID: "1", chapter: chapter("b.mp3")), 0)
        XCTAssertEqual(sut.failures(bookID: "12", chapter: chapter("a.mp3")), 4)
    }

    func test_chapterWithoutRemoteFile_isNotKept() {
        let local = ChapterModel(title: "Local", startTime: 0, duration: 1)

        sut.set(2, bookID: "1", chapter: local)

        XCTAssertEqual(sut.failures(bookID: "1", chapter: local), 0)
    }

    private func chapter(_ name: String) -> ChapterModel {
        ChapterModel(
            title: name,
            startTime: 0,
            duration: 60,
            remoteURL: URL(string: "https://archive.org/download/x/\(name)"),
            expectedBytes: 1
        )
    }
}

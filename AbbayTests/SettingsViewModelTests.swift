//
//  SettingsViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The Settings screen's model: space used, the delete-finished flow, the version line and the
/// Siri & audio status. The library is closures, so no Core Data or disk is involved.
@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var books: [AudioModel] = []
    private var deleted: [[AudioModel]] = []
    private var measuredBytes: Int64 = 0
    private var audioUnavailable = false

    // MARK: - Helpers

    private func finishedBook(_ id: String, totalBytes: Int64 = 1000) -> AudioModel {
        var book = AudioModel(title: id, duration: 100, currentTime: 100, url: LibriVoxIdentity.bookURL(id: id))
        book.librivoxID = id
        book.chapters = [ChapterModel(title: "only", duration: 100, remoteURL: URL(string: "https://e.org/\(id).mp3"))]
        book.totalBytes = totalBytes
        return book
    }

    /// Finished books report a complete tracked download; any other book an incomplete one.
    private func makeSUT(info: [String: Any] = [:]) -> SettingsViewModel {
        let library = SettingsLibrary(
            books: { [unowned self] in books },
            downloadState: { [unowned self] id in
                let book = books.first { $0.librivoxID == id }
                let done = book.map(DownloadHousekeeping.isFinished) ?? false
                return BookDownloadState(chapters: [done ? .downloaded : .waiting], expectedBytes: [1], isPaused: false)
            },
            delete: { [unowned self] in
                deleted.append($0)
                let urls = $0.map(\.url)
                books.removeAll { urls.contains($0.url) }
            }
        )
        return SettingsViewModel(
            settings: AppSettings(store: InMemoryKeyValueStore()),
            library: library,
            measureBytes: { [unowned self] in measuredBytes },
            isAudioUnavailable: { [unowned self] in audioUnavailable },
            bundleInfo: info
        )
    }

    // MARK: - Downloads

    func test_spaceUsed_isUnknownUntilMeasured() async {
        measuredBytes = 5_000_000
        let sut = makeSUT()
        XCTAssertNil(sut.bytesUsed)

        await sut.refresh()

        XCTAssertEqual(sut.bytesUsed, 5_000_000)
    }

    func test_refresh_findsOnlyFinishedDownloads() async {
        var reading = finishedBook("reading")
        reading.currentTime = 10
        books = [finishedBook("done"), reading]
        let sut = makeSUT()

        await sut.refresh()

        XCTAssertEqual(sut.finishedBooks.map(\.title), ["done"])
        XCTAssertTrue(sut.canDeleteFinished)
    }

    func test_nothingFinished_disablesTheDelete() async {
        let sut = makeSUT()

        await sut.refresh()

        XCTAssertFalse(sut.canDeleteFinished)
        sut.askToDeleteFinished()
        XCTAssertFalse(sut.isConfirmingDelete, "nothing to confirm")
    }

    /// Delete asks first; only the confirmation deletes, and the screen then re-measures.
    func test_deleteFinished_asksFirst_thenDeletesThoseBooks_andRemeasures() async {
        books = [finishedBook("one", totalBytes: 2000), finishedBook("two", totalBytes: 3000)]
        measuredBytes = 9000
        let sut = makeSUT()
        await sut.refresh()

        sut.askToDeleteFinished()

        XCTAssertTrue(sut.isConfirmingDelete)
        XCTAssertTrue(deleted.isEmpty, "asking must not delete")
        XCTAssertEqual(sut.finishedBytes, 5000, "the alert names the size it frees")

        measuredBytes = 4000
        await sut.confirmDeleteFinished()

        XCTAssertEqual(deleted.map { $0.map(\.title) }, [["one", "two"]])
        XCTAssertTrue(sut.finishedBooks.isEmpty)
        XCTAssertEqual(sut.bytesUsed, 4000)
        XCTAssertFalse(sut.isConfirmingDelete)
    }

    // MARK: - About

    func test_versionText_showsVersionAndBuild() {
        let sut = makeSUT(info: ["CFBundleShortVersionString": "1.4.0", "CFBundleVersion": "52"])

        XCTAssertEqual(sut.versionText, "1.4.0 (52)")
    }

    func test_versionText_withoutABuild_showsTheVersion() {
        XCTAssertEqual(makeSUT(info: ["CFBundleShortVersionString": "2.0"]).versionText, "2.0")
    }

    func test_audioStatus_reflectsTheLaunchFlag() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isAudioUnavailable)

        audioUnavailable = true

        XCTAssertTrue(sut.isAudioUnavailable, "read live, so the row is right when the screen opens")
    }
}

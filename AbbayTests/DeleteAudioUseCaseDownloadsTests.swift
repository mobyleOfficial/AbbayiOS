//
//  DeleteAudioUseCaseDownloadsTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Deleting a LibriVox book also cancels its downloads and removes its files.
final class DeleteAudioUseCaseDownloadsTests: XCTestCase {
    private final class MockDeleteAudioRepository: DeleteAudioRepositoryProtocol {
        private(set) var deletedURLs: [URL?] = []

        func execute(url: URL?) { deletedURLs.append(url) }
    }

    func test_execute_libriVoxBook_removesItsDownloads() {
        let repository = MockDeleteAudioRepository()
        var removed: [String] = []
        let sut = DeleteAudioUseCase(
            repository: repository,
            removeDownloads: { removed.append($0) },
            snapshotWriter: MockLibrarySnapshotWriter()
        )
        var book = AudioModel()
        book.url = LibriVoxIdentity.bookURL(id: "200")
        book.librivoxID = "200"

        sut.execute(book)

        XCTAssertEqual(removed, ["200"])
        XCTAssertEqual(repository.deletedURLs, [book.url])
    }

    func test_execute_importedBook_leavesDownloadsAlone() {
        var removed: [String] = []
        let sut = DeleteAudioUseCase(
            repository: MockDeleteAudioRepository(),
            removeDownloads: { removed.append($0) },
            snapshotWriter: MockLibrarySnapshotWriter()
        )
        var book = AudioModel()
        book.url = URL(fileURLWithPath: "/imported.m4b")

        sut.execute(book)

        XCTAssertTrue(removed.isEmpty)
    }

    func test_defaultRemoveDownloads_usesContainerDownloads() {
        let downloads = MockBookDownloadManager()
        DependencyContainer.configure(with: MockDependencyContainer(
            player: MockPlayer(),
            loadAudio: MockLoadAudioUseCase(),
            loadAllAudios: MockLoadAllAudiosUseCase(),
            downloads: downloads
        ))
        defer { DependencyContainer.reset() }
        var book = AudioModel()
        book.librivoxID = "200"

        DeleteAudioUseCase(repository: MockDeleteAudioRepository(), snapshotWriter: MockLibrarySnapshotWriter())
            .execute(book)

        XCTAssertEqual(downloads.removed, ["200"])
    }

    func test_execute_forgetsReadAlongForEachBook() {
        var forgotten: [URL?] = []
        let sut = DeleteAudioUseCase(
            repository: MockDeleteAudioRepository(),
            forgetSettings: { _ in },
            forgetReadAlong: { forgotten.append($0) },
            snapshotWriter: MockLibrarySnapshotWriter()
        )
        var first = AudioModel()
        first.url = URL(fileURLWithPath: "/first.m4b")
        var second = AudioModel()
        second.url = URL(fileURLWithPath: "/second.m4b")

        sut.execute([first, second])

        XCTAssertEqual(forgotten, [first.url, second.url])
    }

    /// The live closure drops the book's remembered language and its transcript file, and nobody
    /// else's.
    func test_liveForgetReadAlong_dropsTheLanguageAndTheTranscript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeleteReadAlong-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReadAlongStore(root: root)
        let settings = AppSettings(store: InMemoryKeyValueStore())
        let doomed = try XCTUnwrap(URL(string: "file:///doomed.m4b"))
        let kept = try XCTUnwrap(URL(string: "file:///kept.m4b"))
        for url in [doomed, kept] {
            settings.setReadAlongLanguage("en", for: url)
            store.save(ReadAlongTranscript(language: "en-US"), bookURL: url)
        }

        DeleteAudioUseCase.forgetReadAlongNow(doomed, settings: settings, store: store)

        XCTAssertNil(settings.readAlongLanguage(for: doomed))
        XCTAssertNil(store.load(bookURL: doomed))
        XCTAssertEqual(settings.readAlongLanguage(for: kept), "en")
        XCTAssertNotNil(store.load(bookURL: kept))
    }
}

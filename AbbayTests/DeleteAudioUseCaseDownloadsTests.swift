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
}

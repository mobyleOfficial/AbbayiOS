//
//  DeleteAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 18/01/26.
//

import Foundation

protocol DeleteAudioUseCaseProtocol {
    /// Deletes the books in one go: one library snapshot write however many there are.
    func execute(_ audios: [AudioModel])
}

extension DeleteAudioUseCaseProtocol {
    func execute(_ audio: AudioModel) {
        execute([audio])
    }
}

/// Removes books from the library. Like `SaveAudioUseCase`, it rewrites the App Group snapshot
/// itself, so Siri and CarPlay never keep a deleted book (#85).
final class DeleteAudioUseCase: DeleteAudioUseCaseProtocol {
    private let repository: DeleteAudioRepositoryProtocol
    private let removeDownloads: (String) -> Void
    private let forgetSettings: (URL?) -> Void
    private let forgetReadAlong: (URL?) -> Void
    private let snapshotWriter: LibrarySnapshotWriterProtocol

    /// - Parameter removeDownloads: Cancels a LibriVox book's downloads and deletes its files,
    ///   given its librivoxID. Defaults to the container's download manager, when configured.
    /// - Parameter forgetSettings: Drops the book's own settings (its speed). Defaults to the
    ///   container's settings, on the main thread, when configured.
    /// - Parameter forgetReadAlong: Drops the book's read-along language and transcript file.
    ///   Defaults to the container's settings and `ReadAlongStore.shared`.
    init(
        repository: DeleteAudioRepositoryProtocol = DeleteAudioRepository(),
        removeDownloads: @escaping (String) -> Void = { id in
            guard DependencyContainer.isConfigured else { return }
            DependencyContainer.shared.downloads.remove(bookID: id)
        },
        forgetSettings: @escaping (URL?) -> Void = DeleteAudioUseCase.forgetSettingsOnMain,
        forgetReadAlong: @escaping (URL?) -> Void = DeleteAudioUseCase.forgetReadAlongOnMain,
        snapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
    ) {
        self.repository = repository
        self.removeDownloads = removeDownloads
        self.forgetSettings = forgetSettings
        self.forgetReadAlong = forgetReadAlong
        self.snapshotWriter = snapshotWriter
    }

    func execute(_ audios: [AudioModel]) {
        guard !audios.isEmpty else { return }
        for audio in audios {
            if let id = audio.librivoxID {
                removeDownloads(id)
            }
            forgetSettings(audio.url)
            forgetReadAlong(audio.url)
            // By the book's identity, never its `fileURL`: a moved book's matches no row (#176).
            repository.execute(url: audio.url)
        }
        snapshotWriter.refresh()
    }

    private static func forgetSettingsOnMain(_ url: URL?) {
        onMain {
            // Checked when it runs: tests reset the container between cases.
            guard DependencyContainer.isConfigured else { return }
            DependencyContainer.shared.settings.forgetSpeed(for: url)
        }
    }

    private static func forgetReadAlongOnMain(_ url: URL?) {
        onMain {
            // The file goes even where no container is configured; the language needs settings.
            guard DependencyContainer.isConfigured else {
                forgetReadAlongNow(url, settings: nil, store: .shared)
                return
            }
            forgetReadAlongNow(url, settings: DependencyContainer.shared.settings, store: .shared)
        }
    }

    /// The language the book was remembered in, and its transcript file. The file goes whether or
    /// not read-along is on: it may have been turned off with the book's text still on disk.
    static func forgetReadAlongNow(_ url: URL?, settings: AppSettings?, store: ReadAlongStore) {
        settings?.forgetReadAlong(for: url)
        if let url {
            store.delete(bookURL: url)
        }
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

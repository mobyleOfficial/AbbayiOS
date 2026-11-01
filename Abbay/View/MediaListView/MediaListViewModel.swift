//
//  MediaListViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Foundation
import os

/// The library: its books, import, delete and adding LibriVox books. Owned by the root, above the
/// tabs, so the Search tab adds books through it. Presentation only: the use cases that change the
/// library also rewrite Siri's App Group snapshot (#85).
@MainActor
final class MediaListViewModel: ObservableObject {
    // MARK: - Properties
    private let playback: PlaybackCenter
    /// Weak: the root owns both. Optional so tests that don't present can omit it.
    private weak var presentation: PlayerPresentation?
    private let fileLoader: FileLoaderProtocol
    private let loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol
    private let deleteAudioUseCase: DeleteAudioUseCaseProtocol
    private let loadAudioUseCase: LoadAudioUseCaseProtocol
    private let noticeReporter: NoticeReporting
    /// Imported instead of presenting the picker (`-stubFailingImport`), since UI tests can't drive
    /// the system picker. `nil` outside UI tests.
    private let debugImportURLs: [URL]?
    /// The book loaded at the last switch, so the next one knows which book it left.
    private var loadedURL: URL?

    // MARK: - Observed properties
    @Published
    var audioList = [AudioModel]()
    @Published
    var isShowingFilePicker = false

    // MARK: - Init
    init(
        playback: PlaybackCenter,
        presentation: PlayerPresentation? = nil,
        loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
        deleteAudioUseCase: DeleteAudioUseCaseProtocol = DeleteAudioUseCase(),
        fileLoader: FileLoaderProtocol = FileLoader(),
        loadAudioUseCase: LoadAudioUseCaseProtocol = LoadAudioUseCase(),
        noticeReporter: NoticeReporting = NoticeCenter.shared,
        debugImportURLs: [URL]? = DebugOverrides.importURLs()
    ) {
        self.playback = playback
        self.presentation = presentation
        self.loadAllAudiosUseCase = loadAllAudiosUseCase
        self.deleteAudioUseCase = deleteAudioUseCase
        self.fileLoader = fileLoader
        self.loadAudioUseCase = loadAudioUseCase
        self.noticeReporter = noticeReporter
        self.debugImportURLs = debugImportURLs
        self.loadedURL = playback.state.loadedBook?.url
        defer {
            audioList = loadAllAudiosUseCase.execute()
        }
    }

    // MARK: - Methods
    /// Called when `PlaybackState.loadedBook` changes (the root observes it), so once per switch,
    /// never per tick. Rows are built from `audioList`, which loads once, so re-read both books
    /// from storage: the outgoing one so its row shows (and a replay resumes from) where it
    /// stopped -- the player saves its position before announcing the next book -- and the
    /// incoming one so later presses pass the bookmark the player just made.
    func loadedBookChanged(to book: AudioModel?) {
        let outgoing = loadedURL
        loadedURL = book?.url
        if outgoing != book?.url {
            refreshFromStorage(outgoing)
        }
        refreshFromStorage(book?.url)
    }

    /// A book's chapters were found in its audio or removed, or it was renamed: its row re-reads it.
    func chaptersChanged(ofBookAt url: URL) {
        refreshFromStorage(url)
    }

    private func refreshFromStorage(_ url: URL?) {
        guard let url,
              let index = audioList.firstIndex(where: { $0.url == url }),
              let stored = loadAudioUseCase.execute(url: url) else { return }
        audioList[index] = stored
    }

    /// Deleting the loaded book unloads it, so the bar goes away; deleting the book the details
    /// screen shows closes it.
    func deleteAudio(_ audio: AudioModel) {
        deleteAudios([audio])
    }

    /// Settings' "Delete finished downloads": one use-case call, so one snapshot write for them all.
    func deleteAudios(_ audios: [AudioModel]) {
        for audio in audios {
            if presentation?.presentedBook?.url == audio.url {
                presentation?.close(animated: false)
            }
            if let url = audio.url, playback.state.loadedBook?.url == url || playback.player.url == url {
                playback.unload()
            }
        }
        deleteAudioUseCase.execute(audios)
        audioList.removeAll { row in audios.contains { $0.url == row.url } }
    }

    /// *Import file*: presents the document picker, or under `-stubFailingImport` imports the
    /// debug files straight away.
    func startImport() {
        guard let debugImportURLs else {
            isShowingFilePicker = true
            return
        }
        Task { await importAudio(from: debugImportURLs) }
    }

    /// Files that fail to load are named in a notice, so a missing row is never a mystery (#115).
    /// A file that is a book already in the list (picked again, or found where it moved to) replaces
    /// that row rather than adding one, so the row opens the file where it is now (#196).
    func importAudio(from urls: [URL]) async {
        let result = await fileLoader.load(urls: urls)
        for file in result.loaded {
            if let index = audioList.firstIndex(where: { $0.url == file.url }) {
                audioList[index] = file
            } else {
                audioList.append(file)
            }
        }
        guard !result.failed.isEmpty else { return }
        Log.importing.error(
            "import: \(result.failed.count, privacy: .public) of \(urls.count, privacy: .public) files failed"
        )
        noticeReporter.report(.importFailed(fileNames: result.failed.map(\.lastPathComponent)))
    }

    /// A LibriVox book the details page just saved (which wrote the snapshot).
    func addLibriVoxBook(_ book: AudioModel) {
        guard !audioList.contains(where: { $0.url == book.url }) else { return }
        audioList.append(book)
    }
}

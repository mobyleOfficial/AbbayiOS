//
//  FileLoader.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 20/06/23.
//

import AVFoundation
import os

/// What an import of several files produced: the books that loaded, and the files that didn't.
struct FileImportResult {
    var loaded: [AudioModel] = []
    var failed: [URL] = []
}

protocol FileLoaderProtocol {
    func load(url: URL) async -> AudioModel?
    func load(urls: [URL]) async -> FileImportResult
}

final class FileLoader: FileLoaderProtocol {
    private let loadAudioUseCase: LoadAudioUseCaseProtocol
    private let saveAudioUseCase: SaveAudioUseCaseProtocol
    private let loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol
    private let reimportMatcher: ReimportMatcher

    init(
        loadAudioUseCase: LoadAudioUseCaseProtocol = LoadAudioUseCase(),
        saveAudioUseCase: SaveAudioUseCaseProtocol = SaveAudioUseCase(),
        loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
        reimportMatcher: ReimportMatcher = ReimportMatcher()
    ) {
        self.loadAudioUseCase = loadAudioUseCase
        self.saveAudioUseCase = saveAudioUseCase
        self.loadAllAudiosUseCase = loadAllAudiosUseCase
        self.reimportMatcher = reimportMatcher
    }

    /// Files that fail to load are returned in `failed`, so the library can say which (#115).
    /// New files are saved together at the end: one save, so one snapshot write and one Siri
    /// publish per import, however many files (#84, #85).
    ///
    /// A file that is a book already in the library, found where it moved to (`ReimportMatcher`),
    /// comes back as that book, relinked: its own identity and position with a bookmark to the
    /// picked file, saved to its row instead of as a second book (#196).
    func load(urls: [URL]) async -> FileImportResult {
        var result = FileImportResult()
        var toSave: [AudioModel] = []
        // Loaded once, and only when a picked file isn't a stored book's URL.
        var library: [AudioModel]?
        for url in urls {
            if let file = loadAudioUseCase.execute(url: url) {
                result.loaded.append(file)
            } else if let file = await load(url: url) {
                let books = library ?? loadAllAudiosUseCase.execute()
                if let existing = reimportMatcher.existingBook(for: file, in: books) {
                    let relinked = ReimportMatcher.relink(existing, to: file)
                    Log.importing.info("import: relinked a moved book to \(url.lastPathComponent, privacy: .private)")
                    // One picked file per book: a second can't relink it again.
                    library = books.filter { $0.url != existing.url }
                    result.loaded.append(relinked)
                    toSave.append(relinked)
                } else {
                    library = books
                    result.loaded.append(file)
                    toSave.append(file)
                }
            } else {
                result.failed.append(url)
            }
        }
        save(toSave)
        return result
    }

    /// `nil` when the file can't be opened, or opens but isn't playable audio (a renamed text file,
    /// a damaged download), which would otherwise import as an empty row that never plays.
    func load(url: URL) async -> AudioModel? {
        guard url.startAccessingSecurityScopedResource() else {
            Log.importing.error("import: no access to \(url.lastPathComponent, privacy: .private)")
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true else {
            Log.importing.error("import: not playable audio: \(url.lastPathComponent, privacy: .private)")
            return nil
        }
        var file = AudioModel(url: url)
        await loadDuration(file: &file, asset: asset)
        await loadMetadata(file: &file, asset: asset)
        await loadChapterMetadata(file: &file, asset: asset)

        // Create bookmark while we have security-scoped access
        file.bookmarkData = url.createBookmarkData()

        return file
    }
}

// MARK: - Helpers
extension FileLoader {
    /// Logged only: a failed Core Data save already reports its own notice (`DataStack`), and the
    /// book still shows in the library for this session.
    private func save(_ files: [AudioModel]) {
        do {
            try saveAudioUseCase.execute(files)
        } catch {
            let error = error as NSError
            Log.importing.error(
                """
                import: saving \(files.count, privacy: .public) file(s) failed: \
                \(error.domain, privacy: .public) \(error.code, privacy: .public)
                """
            )
        }
    }

    private func loadDuration(file: inout AudioModel, asset: AVAsset) async {
        guard let duration = try? await asset.load(.duration).seconds else { return }
        file.duration = duration
    }

    private func loadMetadata(file: inout AudioModel, asset: AVAsset) async {
        guard let metadata = try? await asset.load(.commonMetadata) else { return }
        file.title = await loadMetadataItem(metadata, key: .commonKeyTitle) ?? String()
        file.albumName = await loadMetadataItem(metadata, key: .commonKeyAlbumName) ?? String()
        file.artist = await loadMetadataItem(metadata, key: .commonKeyArtist) ?? String()
        file.imageData = await loadMetadataItem(metadata, key: .commonKeyArtwork)
    }

    private func loadChapterMetadata(file: inout AudioModel, asset: AVAsset) async {
        guard let locales = try? await asset.load(.availableChapterLocales),
              let defaultLocale = locales.first?.languageCode else { return }
        let preferredLanguages = Locale.preferredLanguages + [defaultLocale]
        guard let chapters = try? await asset.loadChapterMetadataGroups(
            bestMatchingPreferredLanguages: preferredLanguages
        ) else {
            return
        }
        file.chapters = await loadChapterInfo(chapters)
    }

    private func loadChapterInfo(_ chapters: [AVTimedMetadataGroup]) async -> [ChapterModel] {
        var chapterModels = [ChapterModel]()
        for chapter in chapters {
            let title = await loadMetadataItem(chapter.items, key: .commonKeyTitle) ?? String()
            let timeInfo = chapter.timeRange
            let model = ChapterModel(
                title: title,
                startTime: timeInfo.start.seconds,
                duration: timeInfo.duration.seconds
            )
            chapterModels.append(model)
        }
        return chapterModels
    }

    private func loadMetadataItem<T>(_ items: [AVMetadataItem], key: AVMetadataKey) async -> T? {
        guard let item = items.first(where: { $0.commonKey == key }),
              let value = try? await item.load(.value) as? T else {
            return nil
        }
        return value
    }
}

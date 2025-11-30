//
//  FileLoader.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 20/06/23.
//

import AVFoundation

protocol FileLoaderProtocol {
    func load(url: URL) async -> AudioModel?
    func load(urls: [URL]) async -> [AudioModel]
}

final class FileLoader: FileLoaderProtocol {
    private let loadAudioUseCase: LoadAudioUseCaseProtocol
    private let saveAudioUseCase: SaveAudioUseCaseProtocol

    init(
        loadAudioUseCase: LoadAudioUseCaseProtocol = LoadAudioUseCase(),
        saveAudioUseCase: SaveAudioUseCaseProtocol = SaveAudioUseCase()
    ) {
        self.loadAudioUseCase = loadAudioUseCase
        self.saveAudioUseCase = saveAudioUseCase
    }

    func load(urls: [URL]) async -> [AudioModel] {
        var files = [AudioModel]()
        for url in urls {
            if let file = loadAudioUseCase.execute(url: url) {
                files.append(file)
            } else if let file = await load(url: url) {
                files.append(file)
                try? saveAudioUseCase.execute(file)
            }
        }
        return files
    }

    func load(url: URL) async -> AudioModel? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        let asset = AVAsset(url: url)
        var file = AudioModel(url: url)
        await loadDuration(file: &file, asset: asset)
        await loadMetadata(file: &file, asset: asset)
        await loadChapterMetadata(file: &file, asset: asset)
        url.stopAccessingSecurityScopedResource()
        return file
    }
}

// MARK: - Helpers
extension FileLoader {
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

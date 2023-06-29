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
    private let cache = Cache<URL, AudioModel>.load(withName: "audios")

    func load(urls: [URL]) async -> [AudioModel] {
        var files = [AudioModel]()
        for url in urls {
            if let file = cache[url] {
                files.append(file)
            } else if let file = await load(url: url) {
                cache[url] = file
                files.append(file)
            }
        }
        try? cache.save(withName: "audios")
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
        file.chapters = await loadChapterTitles(chapters)
    }

    private func loadChapterTitles(_ chapters: [AVTimedMetadataGroup]) async -> [String] {
        var chapterTitles = [String]()
        for chapter in chapters {
            if let title: String = await loadMetadataItem(chapter.items, key: .commonKeyTitle) {
                chapterTitles.append(title)
            }
        }
        return chapterTitles
    }

    private func loadMetadataItem<T>(_ items: [AVMetadataItem], key: AVMetadataKey) async -> T? {
        guard let item = items.first(where: { $0.commonKey == key }),
              let value = try? await item.load(.value) as? T else {
            return nil
        }
        return value
    }
}

//
//  DataToModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 08/07/23.
//

import Foundation

extension AudioDataModel {
    var model: AudioModel {
        var model = AudioModel()
        model.title = title ?? String()
        model.albumName = albumName ?? String()
        model.artist = artist ?? String()
        model.duration = duration
        model.currentTime = currentTime
        model.imageData = imageData
        model.bookmarkData = bookmarkData
        model.librivoxID = librivoxID
        model.allowsCellularDownload = allowsCellularDownload
        model.isDownloadPaused = isDownloadPaused
        model.totalBytes = totalBytes
        model.url = URL.resolveBookmark(from: bookmarkData) ?? url
        model.chapters = chapters?.compactMap({ ($0 as? ChapterDataModel)?.model }) ?? []
        return model
    }
}

extension ChapterDataModel {
    var model: ChapterModel {
        var model = ChapterModel()
        model.title = title ?? String()
        model.startTime = startTime
        model.duration = duration
        model.remoteURL = remoteURL
        model.expectedBytes = expectedBytes
        return model
    }
}

//
//  DataToModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 08/07/23.
//

import Foundation

/// A mapped book, and the copy to save when its bookmark was stale (#146).
struct MappedAudio {
    let model: AudioModel
    /// The row's own fields with the fresh bookmark, under the row's stored URL (the save use
    /// case finds the row by `rowURL`, and the resolved one can differ). Nil when nothing changed.
    let refreshedBookmark: AudioModel?
}

extension AudioDataModel {
    /// Call on the context's queue: it faults the chapters. A stale bookmark comes back with
    /// `refreshedBookmark` set; hand that to `StaleBookmarkSaver`, or the refresh is lost.
    func mapped(resolveBookmark: (Data?) -> ResolvedBookmark?) -> MappedAudio {
        var model = mappedFields()
        let resolved = resolveBookmark(bookmarkData)
        // Plays from where the bookmark points now; every row operation still finds the row by
        // the URL it is stored under (`storedURL`, set in `mappedFields`), #176.
        model.url = resolved?.url ?? url
        guard let refreshed = resolved?.refreshedData else {
            return MappedAudio(model: model, refreshedBookmark: nil)
        }
        model.bookmarkData = refreshed
        var toSave = model
        toSave.url = url
        return MappedAudio(model: model, refreshedBookmark: toSave)
    }

    private func mappedFields() -> AudioModel {
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
        model.url = url
        model.storedURL = url
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

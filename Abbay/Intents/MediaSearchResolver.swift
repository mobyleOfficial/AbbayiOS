//
//  MediaSearchResolver.swift
//  Abbay
//
//  Shared by the AbbayIntents extension and the in-app INPlayMediaIntent path so
//  both rank a spoken request identically.
//

import Foundation

enum MediaSearchResolver {
    /// Ranked library candidates for a spoken media request.
    ///
    /// A title-less request — "play in Abbay", "play X on Abbay" (the "on" and
    /// "using" prepositions arrive with an empty search), or a bare "resume" —
    /// carries no media name. `matchAll` deliberately returns nothing for empty
    /// input, so treat title-less as "continue what I was listening to": the
    /// last-played book, else the first in the library so a fresh install still
    /// starts playing instead of erroring.
    static func candidates(
        mediaName: String,
        audios: [AudioModel],
        lastPlayedURL: URL?
    ) -> [AudioModel] {
        let isTitleless = mediaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard isTitleless else {
            return matchAll(input: mediaName, audios: audios, lastPlayedURL: lastPlayedURL)
        }
        if let lastPlayedURL, let resumed = audios.first(where: { $0.url == lastPlayedURL }) {
            return [resumed]
        }
        return Array(audios.prefix(1))
    }

    /// Library snapshot entries as models. The snapshot is the only library view
    /// available cross-process and during a background launch.
    static func audios(from entries: [LibrarySnapshotEntry]) -> [AudioModel] {
        entries.compactMap { entry in
            guard let url = URL(string: entry.urlString) else { return nil }
            var model = AudioModel(url: url)
            model.title = entry.title
            return model
        }
    }
}

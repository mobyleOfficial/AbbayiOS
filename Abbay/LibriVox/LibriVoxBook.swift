//
//  LibriVoxBook.swift
//  Abbay
//

import Foundation

/// A book in the LibriVox catalog, as listed on archive.org.
///
/// Search and popular results are light: they carry only what archive.org's search returns, so
/// `descriptionText` is empty, `sections` is empty and `totalSeconds` is 0. `LibriVoxBookDetails.book`
/// is the full version.
struct LibriVoxBook: Hashable, Identifiable, Codable {
    /// The archive.org identifier (e.g. `alice_in_wonderland_librivox`). It always exists, while a
    /// LibriVox catalog ID may not, so it is the book's identity everywhere: `librivox://book/<id>`,
    /// the download folder and `AudioModel.librivoxID`.
    let id: String
    let title: String
    let authors: String
    /// HTML stripped.
    let descriptionText: String
    /// As archive.org sends it: usually an ISO 639-2 code such as `eng` or `por`.
    let language: String
    let totalSeconds: Double
    /// `https://archive.org/services/img/<id>`
    let coverURL: URL
    let sections: [Section]

    struct Section: Hashable, Codable {
        let title: String
        let seconds: Double
        let listenURL: URL
    }

    /// `language` in the app's language ("English", "inglês"), or as sent when it isn't a code.
    var languageName: String {
        let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return locale.localizedString(forLanguageCode: language) ?? language
    }
}

struct LibriVoxBookDetails: Equatable, Codable {
    let book: LibriVoxBook
    let sectionBytes: [Int64]

    var totalBytes: Int64 {
        sectionBytes.reduce(0, +)
    }
}

extension LibriVoxBook {
    static func coverURL(for identifier: String) -> URL? {
        URL(string: LibriVoxRequests.coverEndpoint + identifier)
    }

    /// A light search result. Nil for anything that isn't an audio item with an identifier and a title.
    init?(searchDoc doc: ArchiveSearchDocDTO) {
        guard let identifier = doc.identifier, !identifier.isEmpty,
              let title = doc.title, !title.isEmpty,
              doc.mediatype == nil || doc.mediatype == "audio",
              let coverURL = Self.coverURL(for: identifier)
        else { return nil }
        self.init(
            id: identifier,
            title: ArchiveCatalog.cleanTitle(title, creator: doc.creators.first),
            authors: doc.creators.joined(separator: ", "),
            descriptionText: "",
            language: doc.languages.first ?? "",
            totalSeconds: 0,
            coverURL: coverURL,
            sections: []
        )
    }
}

extension LibriVoxBookDetails {
    func audioModel(imageData: Data?) -> AudioModel {
        var start = 0.0
        let chapters = book.sections.enumerated().map { index, section in
            defer { start += section.seconds }
            return ChapterModel(
                title: section.title,
                startTime: start,
                duration: section.seconds,
                remoteURL: section.listenURL,
                expectedBytes: index < sectionBytes.count ? sectionBytes[index] : 0
            )
        }
        return AudioModel(
            title: book.title,
            albumName: book.title,
            artist: book.authors,
            duration: book.totalSeconds,
            imageData: imageData,
            chapters: chapters,
            url: LibriVoxIdentity.bookURL(id: book.id),
            librivoxID: book.id,
            totalBytes: totalBytes
        )
    }
}

extension String {
    /// Regex-based on purpose: `NSAttributedString(html:)` must run on the main thread.
    var strippingHTML: String {
        var text = replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        // Last, so "&amp;lt;" stays a literal "&lt;".
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

//
//  LibriVoxBook.swift
//  Abbay
//

import Foundation

struct LibriVoxBook: Hashable, Identifiable {
    let id: String
    let title: String
    let authors: String
    /// HTML stripped.
    let descriptionText: String
    let language: String
    let totalSeconds: Double
    let archiveIdentifier: String
    /// `https://archive.org/services/img/<archiveIdentifier>`
    let coverURL: URL
    let sections: [Section]

    struct Section: Hashable {
        let title: String
        let seconds: Double
        let listenURL: URL
    }
}

struct LibriVoxBookDetails: Equatable {
    let book: LibriVoxBook
    let sectionBytes: [Int64]

    var totalBytes: Int64 {
        sectionBytes.reduce(0, +)
    }
}

extension LibriVoxBook {
    /// Nil when the entry cannot be played: no archive.org item, or a section without a usable URL.
    init?(dto: LibriVoxBookDTO) {
        guard let id = dto.id, !id.isEmpty,
              let archiveURL = dto.urlIArchive.flatMap(URL.init(string:)),
              case let identifier = archiveURL.lastPathComponent,
              !identifier.isEmpty, identifier != "/",
              let coverURL = URL(string: LibriVoxRequests.coverEndpoint + identifier),
              let rawSections = dto.sections, !rawSections.isEmpty
        else { return nil }

        var sections = [Section]()
        for (index, raw) in rawSections.enumerated() {
            guard let listen = raw.listenURL, !listen.isEmpty, let url = URL(string: listen) else { return nil }
            let title = raw.title.flatMap { $0.isEmpty ? nil : $0 } ?? "\(index + 1)"
            sections.append(Section(title: title, seconds: raw.playtime.flatMap(Double.init) ?? 0, listenURL: url))
        }

        self.id = id
        self.title = dto.title ?? ""
        self.authors = (dto.authors ?? [])
            .map { [$0.firstName, $0.lastName].compactMap { $0 }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        self.descriptionText = (dto.description ?? "").strippingHTML
        self.language = dto.language ?? ""
        self.totalSeconds = dto.totaltimesecs ?? sections.reduce(0) { $0 + $1.seconds }
        self.archiveIdentifier = identifier
        self.coverURL = coverURL
        self.sections = sections
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

//
//  LibriVoxDTOs.swift
//  Abbay
//

import Foundation

// MARK: - archive.org search

/// `GET https://archive.org/advancedsearch.php?...&output=json`
struct ArchiveSearchResponseDTO: Decodable {
    let response: Body?

    struct Body: Decodable {
        let docs: [ArchiveSearchDocDTO]?
    }
}

/// archive.org sends `creator` and `language` as a string or an array of strings.
struct ArchiveSearchDocDTO: Decodable {
    let identifier: String?
    let title: String?
    let creators: [String]
    let languages: [String]
    let mediatype: String?

    enum CodingKeys: String, CodingKey {
        case identifier, title, mediatype
        case creators = "creator"
        case languages = "language"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = container.lossyString(.identifier)
        title = container.lossyString(.title)
        creators = container.stringList(.creators)
        languages = container.stringList(.languages)
        mediatype = container.lossyString(.mediatype)
    }
}

// MARK: - archive.org item metadata

/// `GET https://archive.org/metadata/<identifier>`. An unknown identifier answers `{}`.
struct ArchiveMetadataDTO: Decodable {
    let metadata: Metadata?
    let files: [File]?

    struct Metadata: Decodable {
        let title: String?
        let creators: [String]
        let languages: [String]
        /// HTML.
        let description: String?
        let mediatype: String?
        /// `h:mm:ss`
        let runtime: String?

        enum CodingKeys: String, CodingKey {
            case title, description, mediatype, runtime
            case creators = "creator"
            case languages = "language"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = container.lossyString(.title)
            creators = container.stringList(.creators)
            languages = container.stringList(.languages)
            description = container.stringList(.description).first
            mediatype = container.lossyString(.mediatype)
            runtime = container.lossyString(.runtime)
        }
    }

    struct File: Decodable {
        let name: String?
        let format: String?
        let size: String?
        /// `mm:ss`, or seconds as a decimal string.
        let length: String?
        let title: String?
        /// `"1/12"` or `"1"`.
        let track: String?

        enum CodingKeys: String, CodingKey {
            case name, format, size, length, title, track
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = container.lossyString(.name)
            format = container.lossyString(.format)
            size = container.lossyString(.size)
            length = container.lossyString(.length)
            title = container.lossyString(.title)
            track = container.lossyString(.track)
        }

        init(name: String?, format: String?, size: String?, length: String?, title: String?, track: String?) {
            self.name = name
            self.format = format
            self.size = size
            self.length = length
            self.title = title
            self.track = track
        }
    }
}

// MARK: - LibriVox feed

/// `GET /api/feed/audiobooks/`. A 404 body is `{"error": ...}`, so every field is optional.
struct LibriVoxSearchResponseDTO: Decodable {
    let books: [LibriVoxBookDTO]?
}

/// Only what the archive → LibriVox mapping needs. The API sends numbers as strings.
struct LibriVoxBookDTO: Decodable {
    let id: String?
    let urlIArchive: String?
    /// HTML.
    let description: String?
    let sections: [Section]?

    struct Section: Decodable {
        let title: String?
        let listenURL: String?
        let playtime: String?

        enum CodingKeys: String, CodingKey {
            case title
            case listenURL = "listen_url"
            case playtime
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = container.lossyString(.title)
            listenURL = container.lossyString(.listenURL)
            playtime = container.lossyString(.playtime)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, sections, description
        case urlIArchive = "url_iarchive"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lossyString(.id)
        urlIArchive = container.lossyString(.urlIArchive)
        description = container.lossyString(.description)
        sections = try? container.decode([Section].self, forKey: .sections)
    }

    /// The last path component of `url_iarchive`, which is the archive.org identifier.
    var archiveIdentifier: String? {
        guard let url = urlIArchive.flatMap(URL.init(string:)) else { return nil }
        let identifier = url.lastPathComponent
        return identifier.isEmpty || identifier == "/" ? nil : identifier
    }
}

// MARK: - Lenient decoding

private extension KeyedDecodingContainer {
    func lossyString(_ key: Key) -> String? {
        if let string = try? decode(String.self, forKey: key) { return string }
        if let int = try? decode(Int.self, forKey: key) { return String(int) }
        if let double = try? decode(Double.self, forKey: key) { return String(double) }
        return nil
    }

    /// A string or an array of strings, blanks dropped.
    func stringList(_ key: Key) -> [String] {
        let values = (try? decode([String].self, forKey: key)) ?? lossyString(key).map { [$0] } ?? []
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

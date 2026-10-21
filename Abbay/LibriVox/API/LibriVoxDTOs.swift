//
//  LibriVoxDTOs.swift
//  Abbay
//

import Foundation

/// `GET /api/feed/audiobooks/`. A 404 body is `{"error": ...}`, so every field is optional.
struct LibriVoxSearchResponseDTO: Decodable {
    let books: [LibriVoxBookDTO]?
}

/// The API sends most numbers as strings, so numeric fields are read leniently.
struct LibriVoxBookDTO: Decodable {
    let id: String?
    let title: String?
    let description: String?
    let language: String?
    let totaltimesecs: Double?
    let authors: [Author]?
    let urlIArchive: String?
    let sections: [Section]?

    struct Author: Decodable {
        let firstName: String?
        let lastName: String?

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    struct Section: Decodable {
        let title: String?
        let listenURL: String?
        let playtime: String?

        enum CodingKeys: String, CodingKey {
            case title
            case listenURL = "listen_url"
            case playtime
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, language, totaltimesecs, authors, sections
        case urlIArchive = "url_iarchive"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lossyString(.id)
        title = try? container.decode(String.self, forKey: .title)
        description = try? container.decode(String.self, forKey: .description)
        language = try? container.decode(String.self, forKey: .language)
        totaltimesecs = container.lossyDouble(.totaltimesecs)
        authors = try? container.decode([Author].self, forKey: .authors)
        urlIArchive = try? container.decode(String.self, forKey: .urlIArchive)
        sections = try? container.decode([Section].self, forKey: .sections)
    }
}

/// `GET https://archive.org/metadata/<identifier>`
struct ArchiveMetadataDTO: Decodable {
    let files: [File]?

    struct File: Decodable {
        let name: String?
        let size: String?
    }
}

private extension KeyedDecodingContainer {
    func lossyString(_ key: Key) -> String? {
        if let string = try? decode(String.self, forKey: key) { return string }
        if let int = try? decode(Int.self, forKey: key) { return String(int) }
        return nil
    }

    func lossyDouble(_ key: Key) -> Double? {
        if let double = try? decode(Double.self, forKey: key) { return double }
        if let string = try? decode(String.self, forKey: key) { return Double(string) }
        return nil
    }
}

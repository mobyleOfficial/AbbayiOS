//
//  LibriVoxRequests.swift
//  Abbay
//

import Foundation
import NetworkProvider

enum LibriVoxRequests {
    static let archiveSearchEndpoint = "https://archive.org/advancedsearch.php"
    static let feedEndpoint = "https://librivox.org/api/feed/audiobooks/"
    static let metadataEndpoint = "https://archive.org/metadata/"
    static let coverEndpoint = "https://archive.org/services/img/"
    static let downloadEndpoint = "https://archive.org/download/"

    /// The fields a light result needs. archive.org accepts them comma-separated in one `fl[]`,
    /// which matters because `NetworkRequest.queryParams` can't repeat a key.
    static let searchFields = "identifier,title,creator,language,mediatype"
    /// Everything the mapping needs, and nothing else: `extended=1` without `fields` is slow.
    /// `description` is LibriVox's summary, which reads better than archive.org's boilerplate.
    static let feedFields = "{id,url_iarchive,sections,description}"
    /// The feed only improves chapter titles, so the details page never waits long for it.
    static let feedTimeout: TimeInterval = 5

    /// Most-downloaded first, for both search and popular.
    static func archiveSearch(query: String, rows: Int) -> NetworkRequest {
        NetworkRequest(
            endpoint: archiveSearchEndpoint,
            queryParams: [
                "q": query,
                "fl[]": searchFields,
                "sort[]": "downloads desc",
                "rows": String(rows),
                "page": "1",
                "output": "json"
            ]
        )
    }

    /// `format=json&extended=1` on every feed call: without `extended`, `url_iarchive` and
    /// `sections` are missing.
    private static func feed(_ extra: [String: String]) -> NetworkRequest {
        var query = ["format": "json", "extended": "1", "fields": feedFields]
        query.merge(extra) { _, new in new }
        return NetworkRequest(endpoint: feedEndpoint, queryParams: query, timeoutInterval: feedTimeout)
    }

    /// `author=` matches a last name.
    static func author(lastName: String, limit: Int, offset: Int) -> NetworkRequest {
        feed(["author": lastName, "limit": String(limit), "offset": String(offset)])
    }

    static func book(id: String) -> NetworkRequest {
        feed(["id": id])
    }

    static func archiveMetadata(identifier: String) -> NetworkRequest {
        NetworkRequest(endpoint: metadataEndpoint + identifier)
    }

    static func cover(for url: URL) -> NetworkRequest {
        NetworkRequest(endpoint: url.absoluteString)
    }
}

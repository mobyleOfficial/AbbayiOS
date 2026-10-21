//
//  LibriVoxRequests.swift
//  Abbay
//

import Foundation
import NetworkProvider

enum LibriVoxRequests {
    static let feedEndpoint = "https://librivox.org/api/feed/audiobooks/"
    static let metadataEndpoint = "https://archive.org/metadata/"
    static let coverEndpoint = "https://archive.org/services/img/"

    /// `format=json&extended=1` on every call: without `extended`, `url_iarchive` is missing.
    private static func feed(_ extra: [String: String]) -> NetworkRequest {
        var query = ["format": "json", "extended": "1"]
        query.merge(extra) { _, new in new }
        return NetworkRequest(endpoint: feedEndpoint, queryParams: query)
    }

    /// `title=^<prefix>` is a starts-with match; plain `title=` is exact.
    static func titlePrefix(_ prefix: String) -> NetworkRequest {
        feed(["title": "^\(prefix)"])
    }

    static func author(_ name: String) -> NetworkRequest {
        feed(["author": name])
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

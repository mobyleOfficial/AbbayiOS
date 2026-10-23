//
//  LibriVoxClient.swift
//  Abbay
//

import Foundation
import NetworkProvider

protocol LibriVoxClientProtocol {
    /// Light results (no sections, no duration), most-downloaded first.
    func search(_ query: String) async throws -> [LibriVoxBook]
    /// Light results, most-downloaded first.
    func popular() async throws -> [LibriVoxBook]
    /// The full book: chapters, durations and sizes.
    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails
    func coverData(for book: LibriVoxBook) async -> Data?
}

enum LibriVoxClientError: Error, Equatable {
    /// archive.org has no audio item with chapter files under this identifier.
    case notAnAudiobook
}

/// The LibriVox catalog, served by two sources.
///
/// - archive.org finds books (search and popular) and describes them (item metadata: title,
///   creator, language, description and every file with its size and length).
/// - LibriVox's API, when it lists the item, supplies clean chapter titles. It is matched by
///   creator's last name and `url_iarchive`. Without a match, chapters come from the item's files.
///
/// See `Policy` for what is cached and for how long.
final class LibriVoxClient: LibriVoxClientProtocol {
    enum Policy {
        static let popularMaxAge: TimeInterval = 24 * 60 * 60
        static let detailsMaxAge: TimeInterval = 7 * 24 * 60 * 60
        /// A found mapping is kept for good; a miss is retried after this.
        static let missedMappingMaxAge: TimeInterval = 7 * 24 * 60 * 60
        static let searchRows = 50
        static let popularRows = 30
        /// `limit` of 1000 or more is refused ("Too many records").
        static let authorPageSize = 100
        static let authorPageCap = 3
        /// Search results are kept in memory for the session, up to this many queries.
        static let sessionSearchLimit = 50
    }

    /// What the cache stores per archive identifier. `librivoxID == nil` records a miss.
    struct Mapping: Codable, Equatable {
        let librivoxID: String?
    }

    static let popularKey = "popular"

    static func detailsKey(_ identifier: String) -> String { "details.\(identifier)" }
    static func mappingKey(_ identifier: String) -> String { "mapping.\(identifier)" }

    private let network: NetworkProviderProtocol
    private let cache: CatalogCache
    private let lock = NSLock()
    private var sessionSearches = [String: [LibriVoxBook]]()
    private var popularRefresh: Task<Void, Never>?

    init(network: NetworkProviderProtocol = NetworkProvider(), cache: CatalogCache = .shared) {
        self.network = network
        self.cache = cache
    }

    // MARK: - Search

    func search(_ query: String) async throws -> [LibriVoxBook] {
        guard let lucene = ArchiveSearchQuery.search(query) else { return [] }
        let key = ArchiveSearchQuery.normalized(query)
        if let hit = withLock({ sessionSearches[key] }) { return hit }

        let books = try await searchArchive(lucene, rows: Policy.searchRows)
        withLock {
            if sessionSearches.count >= Policy.sessionSearchLimit { sessionSearches.removeAll() }
            sessionSearches[key] = books
        }
        return books
    }

    // MARK: - Popular

    /// A cached list is returned at once, even when stale; a stale one is then refreshed in the
    /// background for next time, and kept if the refresh fails.
    func popular() async throws -> [LibriVoxBook] {
        if let cached = cache.read([LibriVoxBook].self, key: Self.popularKey, maxAge: Policy.popularMaxAge) {
            if !cached.isFresh { refreshPopularInBackground() }
            return cached.value
        }
        return try await fetchPopular()
    }

    /// The background refresh in flight, if any. Exposed so tests can await it.
    var pendingPopularRefresh: Task<Void, Never>? {
        withLock { popularRefresh }
    }

    private func refreshPopularInBackground() {
        withLock {
            guard popularRefresh == nil else { return }
            popularRefresh = Task { [weak self] in
                _ = try? await self?.fetchPopular()
                self?.withLock { self?.popularRefresh = nil }
            }
        }
    }

    @discardableResult
    private func fetchPopular() async throws -> [LibriVoxBook] {
        let books = try await searchArchive(ArchiveSearchQuery.popular, rows: Policy.popularRows)
        if !books.isEmpty { cache.write(books, key: Self.popularKey) }
        return books
    }

    // MARK: - Details

    /// Cached for `Policy.detailsMaxAge`. An expired entry is still returned if the refresh fails.
    ///
    /// When LibriVox can't be reached, the book is built from archive.org's files but not cached,
    /// so the clean chapter titles come back on the next open.
    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails {
        let key = Self.detailsKey(book.id)
        let cached = cache.read(LibriVoxBookDetails.self, key: key, maxAge: Policy.detailsMaxAge)
        if let cached, cached.isFresh { return cached.value }
        let fetched: (details: LibriVoxBookDetails, isComplete: Bool)
        do {
            fetched = try await fetchDetails(identifier: book.id)
        } catch {
            if let cached { return cached.value }
            throw error
        }
        guard fetched.isComplete else { return cached?.value ?? fetched.details }
        cache.write(fetched.details, key: key)
        return fetched.details
    }

    func coverData(for book: LibriVoxBook) async -> Data? {
        let request = LibriVoxRequests.cover(for: book.coverURL)
        guard let response: NetworkResponse<Data> = try? await network.makeRequest(request),
              (200..<300).contains(response.statusCode),
              !response.content.isEmpty
        else { return nil }
        return response.content
    }
}

// MARK: - Private

private enum MappingLookup {
    case matched(LibriVoxBookDTO)
    case noMatch
    /// LibriVox couldn't be reached.
    case unavailable

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

private extension LibriVoxClient {
    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func searchArchive(_ lucene: String, rows: Int) async throws -> [LibriVoxBook] {
        let response: NetworkResponse<ArchiveSearchResponseDTO> = try await network.makeRequest(
            LibriVoxRequests.archiveSearch(query: lucene, rows: rows)
        )
        guard (200..<300).contains(response.statusCode) else { throw NetworkError.httpStatus(response.statusCode) }
        var seen = Set<String>()
        return (response.content.response?.docs ?? [])
            .compactMap(LibriVoxBook.init(searchDoc:))
            .filter { seen.insert($0.id).inserted }
    }

    /// `isComplete` is false when LibriVox couldn't be asked, so the chapters may be the fallback.
    func fetchDetails(identifier: String) async throws -> (details: LibriVoxBookDetails, isComplete: Bool) {
        let response: NetworkResponse<ArchiveMetadataDTO> = try await network.makeRequest(
            LibriVoxRequests.archiveMetadata(identifier: identifier)
        )
        guard (200..<300).contains(response.statusCode) else { throw NetworkError.httpStatus(response.statusCode) }
        let item = response.content
        guard let metadata = item.metadata,
              metadata.mediatype == nil || metadata.mediatype == "audio",
              let coverURL = LibriVoxBook.coverURL(for: identifier)
        else { throw LibriVoxClientError.notAnAudiobook }

        let files = item.files ?? []
        var sizes = [String: Int64]()
        var lengths = [String: Double]()
        for file in files {
            guard let name = file.name else { continue }
            sizes[name] = file.size.flatMap { Int64($0) } ?? 0
            lengths[name] = ArchiveCatalog.seconds(fromLength: file.length)
        }

        let creator = metadata.creators.first
        let lookup = await libriVoxEntry(identifier: identifier, creator: creator)
        var sections = [LibriVoxBook.Section]()
        var summary = metadata.description
        if case let .matched(match) = lookup, let mapped = Self.sections(from: match.sections ?? [], lengths: lengths) {
            sections = mapped
            if let description = match.description, !description.strippingHTML.isEmpty { summary = description }
        } else {
            sections = ArchiveCatalog.chapterFiles(files).compactMap {
                ArchiveCatalog.fallbackSection($0, identifier: identifier)
            }
        }
        guard !sections.isEmpty else { throw LibriVoxClientError.notAnAudiobook }

        let sum = sections.reduce(0) { $0 + $1.seconds }
        let book = LibriVoxBook(
            id: identifier,
            title: ArchiveCatalog.cleanTitle(metadata.title ?? identifier, creator: creator),
            authors: metadata.creators.joined(separator: ", "),
            descriptionText: (summary ?? "").strippingHTML,
            language: metadata.languages.first ?? "",
            totalSeconds: sum > 0 ? sum : ArchiveCatalog.seconds(fromLength: metadata.runtime) ?? 0,
            coverURL: coverURL,
            sections: sections
        )
        let sectionBytes = sections.map { sizes[$0.listenURL.lastPathComponent] ?? 0 }
        return (LibriVoxBookDetails(book: book, sectionBytes: sectionBytes), !lookup.isUnavailable)
    }

    /// Nil when a section has no usable URL, so the whole book falls back to archive.org's files.
    static func sections(
        from raw: [LibriVoxBookDTO.Section],
        lengths: [String: Double]
    ) -> [LibriVoxBook.Section]? {
        guard !raw.isEmpty else { return nil }
        var sections = [LibriVoxBook.Section]()
        for (index, section) in raw.enumerated() {
            guard let listen = section.listenURL, !listen.isEmpty, let url = URL(string: listen) else { return nil }
            let title = section.title.flatMap { $0.isEmpty ? nil : $0 } ?? "\(index + 1)"
            let seconds = section.playtime.flatMap(Double.init) ?? lengths[url.lastPathComponent] ?? 0
            sections.append(LibriVoxBook.Section(title: title, seconds: seconds, listenURL: url))
        }
        return sections
    }

    // MARK: Mapping archive.org → LibriVox

    /// The LibriVox entry for this archive item.
    ///
    /// A known LibriVox ID is fetched directly. If that ID no longer exists, the mapping is
    /// forgotten and looked up again. A recent miss skips the lookup. A network failure records
    /// no miss, so a flaky connection doesn't hide a real match for a week.
    func libriVoxEntry(identifier: String, creator: String?) async -> MappingLookup {
        let key = Self.mappingKey(identifier)
        if let known = cache.read(Mapping.self, key: key, maxAge: Policy.missedMappingMaxAge) {
            if let id = known.value.librivoxID {
                guard let books = try? await feedBooks(LibriVoxRequests.book(id: id)) else { return .unavailable }
                if let match = books.first(where: { $0.archiveIdentifier == identifier }) { return .matched(match) }
                cache.remove(key: key)
            } else if known.isFresh {
                return .noMatch
            }
        }

        guard let lastName = ArchiveCatalog.lastName(of: creator) else { return .noMatch }
        for page in 0..<Policy.authorPageCap {
            let request = LibriVoxRequests.author(
                lastName: lastName,
                limit: Policy.authorPageSize,
                offset: page * Policy.authorPageSize
            )
            guard let books = try? await feedBooks(request) else { return .unavailable }
            if let match = books.first(where: { $0.archiveIdentifier == identifier }), let id = match.id {
                cache.write(Mapping(librivoxID: id), key: key)
                return .matched(match)
            }
            if books.count < Policy.authorPageSize { break }
        }
        cache.write(Mapping(librivoxID: nil), key: key)
        return .noMatch
    }

    /// A 404 means "no match" and arrives either as a decoding error carrying 404 or as a 404 response.
    func feedBooks(_ request: NetworkRequest) async throws -> [LibriVoxBookDTO] {
        let response: NetworkResponse<LibriVoxSearchResponseDTO>
        do {
            response = try await network.makeRequest(request)
        } catch NetworkError.decoding(_, 404) {
            return []
        }
        if response.statusCode == 404 { return [] }
        guard (200..<300).contains(response.statusCode) else { throw NetworkError.httpStatus(response.statusCode) }
        return response.content.books ?? []
    }
}

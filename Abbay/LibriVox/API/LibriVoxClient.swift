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
    /// The same, plus `onPreview` as soon as archive.org has answered: the book from archive.org
    /// alone (file-name chapter titles), or an expired cached copy, while LibriVox is still being
    /// asked for its titles and description. Not called for a fresh cache hit.
    func details(
        for book: LibriVoxBook,
        onPreview: @escaping @MainActor (LibriVoxBookDetails) -> Void
    ) async throws -> LibriVoxBookDetails
    func coverData(for book: LibriVoxBook) async -> Data?
}

extension LibriVoxClientProtocol {
    /// Without a preview: the final details only.
    func details(
        for book: LibriVoxBook,
        onPreview: @escaping @MainActor (LibriVoxBookDetails) -> Void
    ) async throws -> LibriVoxBookDetails {
        try await details(for: book)
    }
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
    private let covers: CoverDataLoading
    private let lock = NSLock()
    private var sessionSearches = [String: [LibriVoxBook]]()
    private var popularRefresh: Task<Void, Never>?

    /// `covers` is the app's cover loader, so the cover saved with a book comes from the same disk
    /// cache, through the same host allowlist, as the one on screen.
    init(
        network: NetworkProviderProtocol = NetworkProvider(),
        cache: CatalogCache = .shared,
        covers: CoverDataLoading = AsyncImageLoader.shared
    ) {
        self.network = network
        self.cache = cache
        self.covers = covers
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
        try await details(for: book, onPreview: { _ in })
    }

    /// archive.org and the LibriVox lookup run at the same time when the book already names its
    /// creator (a search or popular result does), so the page waits for archive.org alone: about a
    /// second, where LibriVox's author feed takes 2 to 11 (#258).
    func details(
        for book: LibriVoxBook,
        onPreview: @escaping @MainActor (LibriVoxBookDetails) -> Void
    ) async throws -> LibriVoxBookDetails {
        let key = Self.detailsKey(book.id)
        let cached = cache.read(LibriVoxBookDetails.self, key: key, maxAge: Policy.detailsMaxAge)
        if let cached, cached.isFresh { return cached.value }

        // Records no miss: until archive.org confirms the creator, a miss may be the wrong author's.
        let early = book.creator.map { creator in
            Task { await self.libriVoxEntry(identifier: book.id, creator: creator, recordsMiss: false) }
        }
        let item: ArchiveItem
        do {
            item = try await fetchArchiveItem(identifier: book.id)
        } catch {
            early?.cancel()
            if let cached { return cached.value }
            throw error
        }
        if let preview = cached?.value ?? (try? item.details(with: .noMatch)) {
            await onPreview(preview)
        }

        let lookup: MappingLookup
        if let early, item.creator == book.creator {
            lookup = await early.value
            if case .noMatch = lookup { cache.write(Mapping(librivoxID: nil), key: Self.mappingKey(book.id)) }
        } else {
            early?.cancel()
            lookup = await libriVoxEntry(identifier: book.id, creator: item.creator)
        }
        let fetched = try item.details(with: lookup)
        guard !lookup.isUnavailable else { return cached?.value ?? fetched }
        cache.write(fetched, key: key)
        return fetched
    }

    /// The artwork saved with a downloaded book, through the cover loader rather than a request of
    /// its own: the details page has usually just loaded it, so it comes from the disk cache, and a
    /// URL off `CoverHostPolicy` is refused (#175).
    func coverData(for book: LibriVoxBook) async -> Data? {
        await covers.coverData(for: book.coverURL)
    }
}

// MARK: - Private

/// An archive.org item's metadata, turned into the book once the LibriVox lookup has answered.
private struct ArchiveItem {
    let identifier: String
    let metadata: ArchiveMetadataDTO.Metadata
    let files: [ArchiveMetadataDTO.File]
    let coverURL: URL

    var creator: String? { metadata.creators.first }

    /// The chapters are LibriVox's when it matched, else the item's chapter files.
    func details(with lookup: MappingLookup) throws -> LibriVoxBookDetails {
        var sizes = [String: Int64]()
        var lengths = [String: Double]()
        for file in files {
            guard let name = file.name else { continue }
            sizes[name] = file.size.flatMap { Int64($0) } ?? 0
            lengths[name] = ArchiveCatalog.seconds(fromLength: file.length)
        }

        var sections = [LibriVoxBook.Section]()
        var summary = metadata.description
        if case let .matched(match) = lookup,
           let mapped = LibriVoxClient.sections(from: match.sections ?? [], lengths: lengths) {
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
            sections: sections,
            creator: creator
        )
        let sectionBytes = sections.map { sizes[$0.listenURL.lastPathComponent] ?? 0 }
        return LibriVoxBookDetails(book: book, sectionBytes: sectionBytes)
    }
}

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

    func fetchArchiveItem(identifier: String) async throws -> ArchiveItem {
        let response: NetworkResponse<ArchiveMetadataDTO> = try await network.makeRequest(
            LibriVoxRequests.archiveMetadata(identifier: identifier)
        )
        guard (200..<300).contains(response.statusCode) else { throw NetworkError.httpStatus(response.statusCode) }
        let item = response.content
        guard let metadata = item.metadata,
              metadata.mediatype == nil || metadata.mediatype == "audio",
              let coverURL = LibriVoxBook.coverURL(for: identifier)
        else { throw LibriVoxClientError.notAnAudiobook }
        return ArchiveItem(identifier: identifier, metadata: metadata, files: item.files ?? [], coverURL: coverURL)
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
            // "0" and "" mean LibriVox doesn't know; the archive file's own length does.
            let playtime = section.playtime.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
            let seconds = playtime ?? lengths[url.lastPathComponent] ?? 0
            sections.append(LibriVoxBook.Section(title: title, seconds: seconds, listenURL: url))
        }
        return sections
    }

    // MARK: Mapping archive.org → LibriVox

    /// The LibriVox entry for this archive item.
    ///
    /// A known LibriVox ID is fetched directly. If that ID no longer exists, the mapping is
    /// forgotten and looked up again. A recent miss skips the lookup, and so does a creator the
    /// last-name rule can't use (missing, or "Various"). The first author page is read alone,
    /// since most authors fit in it; the rest of the capped pages are read together. A network
    /// failure or timeout records no miss, so a flaky connection doesn't hide a real match for a week.
    func libriVoxEntry(identifier: String, creator: String?, recordsMiss: Bool = true) async -> MappingLookup {
        let key = Self.mappingKey(identifier)
        if let known = cache.read(Mapping.self, key: key, maxAge: Policy.missedMappingMaxAge) {
            if let id = known.value.librivoxID {
                guard let books = try? await feedBooks(LibriVoxRequests.book(id: id)) else { return .unavailable }
                if let match = Self.match(in: books, identifier: identifier) { return .matched(match) }
                cache.remove(key: key)
            } else if known.isFresh {
                return .noMatch
            }
        }

        let isVarious = creator?.trimmingCharacters(in: .whitespaces).lowercased() == "various"
        let lookup: MappingLookup
        if !isVarious, let lastName = ArchiveCatalog.lastName(of: creator) {
            lookup = await lookUp(identifier, byAuthor: lastName)
        } else {
            lookup = .noMatch
        }
        switch lookup {
        case let .matched(match):
            cache.write(Mapping(librivoxID: match.id), key: key)
        case .noMatch:
            if recordsMiss { cache.write(Mapping(librivoxID: nil), key: key) }
        case .unavailable:
            break
        }
        return lookup
    }

    /// The first page alone, since most authors fit in it; then the rest of the capped pages together.
    func lookUp(_ identifier: String, byAuthor lastName: String) async -> MappingLookup {
        guard let first = try? await authorPage(lastName, page: 0) else { return .unavailable }
        if let match = Self.match(in: first, identifier: identifier) { return .matched(match) }
        guard first.count >= Policy.authorPageSize, Policy.authorPageCap > 1 else { return .noMatch }

        let rest = await withTaskGroup(of: [LibriVoxBookDTO]?.self) { group in
            for page in 1..<Policy.authorPageCap {
                group.addTask { try? await self.authorPage(lastName, page: page) }
            }
            var collected = [[LibriVoxBookDTO]?]()
            for await result in group { collected.append(result) }
            return collected
        }
        if let match = Self.match(in: rest.compactMap { $0 }.flatMap { $0 }, identifier: identifier) {
            return .matched(match)
        }
        return rest.contains { $0 == nil } ? .unavailable : .noMatch
    }

    func authorPage(_ lastName: String, page: Int) async throws -> [LibriVoxBookDTO] {
        try await feedBooks(LibriVoxRequests.author(
            lastName: lastName,
            limit: Policy.authorPageSize,
            offset: page * Policy.authorPageSize
        ))
    }

    static func match(in books: [LibriVoxBookDTO], identifier: String) -> LibriVoxBookDTO? {
        books.first { $0.archiveIdentifier == identifier && $0.id != nil }
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

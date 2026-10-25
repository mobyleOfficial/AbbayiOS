//
//  AudioDomainIntents.swift
//  Abbay
//

import AppIntents
import Foundation
#if canImport(MediaIntents)
import MediaIntents
#endif

// MARK: - What Siri asked for, independent of the SDK

/// A Siri audio request reduced to what Abbay can act on. iOS 27's `AudioSearch.Criteria` maps
/// onto it one to one (`AudioDomainBookQuery.request(for:)`); keeping the matching on this type
/// keeps it a pure function that the unit suite checks on every runtime, not just iOS 27.
enum AudioDomainRequest: Equatable {
    /// "Play an audiobook in Abbay": no title.
    case unspecified
    /// What the person said, for example "the goblet of fire".
    case query(String)
    /// The system already knows which item: a URL from the request or from on-screen content.
    case urls([URL])
}

enum AudioDomainMatcher {
    /// The books to offer for `request`, best first. Siri plays the first one.
    ///
    /// - `unspecified`: the last-played book first, then the rest of the library, like the
    ///   entity suggestions (and capped the same way).
    /// - `query`: the same fuzzy title rules as the other Siri paths (`matchAll`).
    /// - `urls`: books whose URL, or the URL their row is saved under, is one of `urls`.
    static func books(for request: AudioDomainRequest, library: [AudioModel], lastPlayedURL: URL?) -> [AudioModel] {
        switch request {
        case .unspecified:
            var ordered = library
            if let lastPlayedURL, let index = ordered.firstIndex(where: { $0.url == lastPlayedURL }) {
                ordered.insert(ordered.remove(at: index), at: 0)
            }
            return Array(ordered.prefix(AudiobookEntityQuery.suggestionLimit))
        case .query(let text):
            return matchAll(input: text, audios: library, lastPlayedURL: lastPlayedURL)
        case .urls(let urls):
            let wanted = Set(urls.map(\.absoluteString))
            return library.filter { book in
                [book.url, book.storedURL].contains { $0.map { wanted.contains($0.absoluteString) } ?? false }
            }
        }
    }
}

// MARK: - iOS 27 audio domain

#if canImport(MediaIntents)

/// An Abbay book in iOS 27's App Intents audio domain (`.audio.audiobook`, schema
/// `MediaBookEntity`). Separate from `AudiobookEntity`, which phrases and Shortcuts use on iOS 17+:
/// a schema entity can't be back-deployed, and the two must not share a type.
@available(iOS 27, *)
@AppEntity(schema: .audio.audiobook)
struct AudioDomainBookEntity {
    static let defaultQuery = AudioDomainBookQuery()

    /// The book's URL string, like `AudiobookEntity.id`.
    let id: String
    var title: String?
    var author: String?
    // The schema requires every one of its properties. Abbay has no data for these, so they stay nil.
    var genre: String?
    var narrator: String?
    var publisher: String?
    var seriesTitle: String?
    var releaseDate: Date?
    var purchaseDate: Date?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title ?? "")")
    }

    var url: URL? {
        URL(string: id)
    }

    init(id: String, title: String?, author: String?) {
        self.id = id
        self.title = title
        self.author = author
    }

    init?(model: AudioModel) {
        guard let url = model.url else { return nil }
        self.init(id: url.absoluteString, title: model.title, author: model.artist.isEmpty ? nil : model.artist)
    }
}

/// Finds books for Siri: by id (`EntityQuery`) and from an audio request
/// (`IntentValueQuery` over `AudioSearch`).
@available(iOS 27, *)
struct AudioDomainBookQuery: EntityQuery, IntentValueQuery {
    func entities(for identifiers: [AudioDomainBookEntity.ID]) async throws -> [AudioDomainBookEntity] {
        let wanted = Set(identifiers)
        let found = AudiobookLibrary.all()
            .compactMap(AudioDomainBookEntity.init(model:))
            .filter { wanted.contains($0.id) }
        DependencyContainer.diagnostics.record("query audio book byId asked=\(identifiers.count) found=\(found.count)")
        return found
    }

    func suggestedEntities() async throws -> [AudioDomainBookEntity] {
        books(for: .unspecified)
    }

    func values(for audioSearch: AudioSearch) async throws -> [AudioDomainBookEntity] {
        let request = Self.request(for: audioSearch.criteria)
        let found = books(for: request)
        DependencyContainer.diagnostics.record("query audio search \(request.kind) found=\(found.count)")
        return found
    }

    static func request(for criteria: AudioSearch.Criteria) -> AudioDomainRequest {
        switch criteria {
        case .unspecified: .unspecified
        case .searchQuery(let text): .query(text)
        case .url(let urls): .urls(urls)
        @unknown default: .unspecified
        }
    }

    private func books(for request: AudioDomainRequest) -> [AudioDomainBookEntity] {
        AudioDomainMatcher.books(
            for: request,
            library: AudiobookLibrary.all(),
            lastPlayedURL: DependencyContainer.lastPlayed.lastPlayedURL()
        )
        .compactMap(AudioDomainBookEntity.init(model:))
    }
}

/// The audio items Abbay can play: only audiobooks.
@available(iOS 27, *)
@UnionValue
enum AudioDomainItem {
    case audiobook(AudioDomainBookEntity)
}

/// "Play <book>" through iOS 27's audio domain (`.audio.playAudio`). Siri resolves the book with
/// `AudioDomainBookQuery`, then runs this. iOS 17–26 keep SiriKit's `INPlayMediaIntent` and the
/// App Shortcuts in `AbbayIntents.swift`; this only adds a path on iOS 27.
@available(iOS 27, *)
@AppIntent(schema: .audio.playAudio)
struct PlayAudioDomainIntent: AudioPlaybackIntent {
    var audioEntity: AudioDomainItem
    @Parameter(default: [])
    var playbackAttributes: Set<AudioDomainPlaybackAttribute>
    var warmupAudioQueueResult: AudioDomainWarmupResult?
    var queueLocation: AudioDomainQueueLocation?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DependencyContainer.diagnostics.record("appintent PlayAudioDomainIntent fired")
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(abbayAudioUnavailableDialog))
        }
        switch audioEntity {
        case .audiobook(let book):
            return .result(dialog: IntentDialog(abbayPlayBook(at: book.url)))
        }
    }
}

/// Shuffle and repeat, which the schema requires. An audiobook plays in order, so both are ignored.
@available(iOS 27, *)
@AppEnum(schema: .audio.playbackAttributes)
enum AudioDomainPlaybackAttribute: String {
    case shuffle
    case `repeat`

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .shuffle: "Shuffle",
        .repeat: "Repeat"
    ]
}

/// Play next or at the end of the queue, which the schema requires. Abbay has no queue: a request
/// plays the book now.
@available(iOS 27, *)
@AppEnum(schema: .audio.queueInsertionLocation)
enum AudioDomainQueueLocation: String {
    case next
    case tail

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .next: "Play next",
        .tail: "Play last"
    ]
}

/// A queue warmed up ahead of play (`.audio.warmupAudioQueue`). Abbay doesn't warm one up, so this
/// is never produced; the schema still requires the type. Transient: there is nothing to look up.
@available(iOS 27, *)
@AppEntity(schema: .audio.warmupAudioQueueResult)
struct AudioDomainWarmupResult: TransientAppEntity {
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Abbay")
    }

    init() {}
}

#endif

extension AudioDomainRequest {
    /// For the diagnostics trail: the request's kind, never what was said.
    var kind: String {
        switch self {
        case .unspecified: "unspecified"
        case .query: "query"
        case .urls: "urls"
        }
    }
}

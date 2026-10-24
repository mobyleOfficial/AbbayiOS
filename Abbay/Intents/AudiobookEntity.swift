//
//  AudiobookEntity.swift
//  Abbay
//

import AppIntents
import Foundation

/// Reads the library for AppIntents code paths.
///
/// Entity queries and intent bodies can run before the normal launch path has
/// configured `DependencyContainer` (Siri may resolve a parameter while the app
/// is still coming up), and `DependencyContainer.shared` traps when unconfigured.
/// Fall back to the App Group snapshot, which the app rewrites on every library
/// mutation, so parameter resolution never traps and never comes back empty just
/// because Core Data is not up yet.
enum AudiobookLibrary {
    static func all() -> [AudioModel] {
        if DependencyContainer.isConfigured {
            let audios = DependencyContainer.shared.loadAllAudios.execute()
            if !audios.isEmpty {
                return audios
            }
        }
        return DependencyContainer.librarySnapshot.read().compactMap { entry in
            guard let url = URL(string: entry.urlString) else { return nil }
            var model = AudioModel(url: url)
            model.title = entry.title
            return model
        }
    }
}

/// A single audiobook, exposed to Siri and Shortcuts as a parameter value.
///
/// This is what makes the one-shot phrase "Play <title> in Abbay" possible.
/// AppShortcut phrase interpolation accepts `AppEntity` and `AppEnum` parameters
/// only — a `String` parameter is rejected by the toolchain, which is why the
/// by-name intent used to need a second "Which audiobook?" turn.
struct AudiobookEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Audiobook")
    static let defaultQuery = AudiobookEntityQuery()

    /// The book's URL string — the same identifier the media snapshot and
    /// `LastPlayedStore` use, so entities round-trip across processes.
    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    var url: URL? {
        URL(string: id)
    }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init?(model: AudioModel) {
        guard let url = model.url else { return nil }
        self.init(id: url.absoluteString, title: model.title)
    }
}

struct AudiobookEntityQuery: EntityQuery, EntityStringQuery {
    /// Keeps the AppShortcuts phrase budget in range. Apple caps an app at 1,000
    /// trigger phrases across all shortcuts, counting every parameter permutation,
    /// so only the most recent slice of the library gets voice phrases. Books past
    /// the cap are still reachable — `entities(matching:)` resolves any title.
    static let suggestionLimit = 40

    func entities(for identifiers: [AudiobookEntity.ID]) async throws -> [AudiobookEntity] {
        let wanted = Set(identifiers)
        let found = AudiobookLibrary.all()
            .compactMap(AudiobookEntity.init(model:))
            .filter { wanted.contains($0.id) }
        DependencyContainer.diagnostics.record("query book byId asked=\(identifiers.count) found=\(found.count)")
        return found
    }

    func suggestedEntities() async throws -> [AudiobookEntity] {
        let lastPlayed = DependencyContainer.lastPlayed.lastPlayedURL()
        var ordered = AudiobookLibrary.all().compactMap(AudiobookEntity.init(model:))
        // Last-played first so the most likely spoken title is inside the cap.
        if let lastPlayed, let index = ordered.firstIndex(where: { $0.url == lastPlayed }) {
            let recent = ordered.remove(at: index)
            ordered.insert(recent, at: 0)
        }
        let suggestions = Array(ordered.prefix(Self.suggestionLimit))
        DependencyContainer.diagnostics.record("query book suggested count=\(suggestions.count)")
        return suggestions
    }

    /// Free-form resolution. Siri calls this with whatever the user actually said,
    /// so it uses the same fuzzy rules as the media-domain handler rather than
    /// requiring an exact title.
    func entities(matching string: String) async throws -> [AudiobookEntity] {
        let library = AudiobookLibrary.all()
        let matches = matchAll(
            input: string,
            audios: library,
            lastPlayedURL: DependencyContainer.lastPlayed.lastPlayedURL()
        )
        let entities = matches.compactMap(AudiobookEntity.init(model:))
        DependencyContainer.diagnostics.record("query book matching found=\(entities.count) library=\(library.count)")
        return entities
    }
}

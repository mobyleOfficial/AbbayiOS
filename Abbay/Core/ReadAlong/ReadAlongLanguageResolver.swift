//
//  ReadAlongLanguageResolver.swift
//  Abbay
//

import Foundation

/// Which language a book is read in, for the speech engine: the player's read-along text and the
/// chapter search (`ChapterFinder`) ask the same way, so a book is detected once and both read it in
/// the same language.
///
/// The book's own setting wins (a bare code from LibriVox is matched to a supported locale and
/// saved back as one); else a short sample is scored with each candidate whose model is already
/// installed; else the in-app language. The result is saved for the book.
@MainActor
struct ReadAlongLanguageResolver {
    enum Outcome: Equatable {
        case resolved(String)
        /// Detection needs the audio at the asked time, and it isn't on the device.
        case audioMissing
        /// `isCurrent` turned false part way: the caller moved on.
        case cancelled
    }

    /// Seconds of audio each candidate language transcribes for detection.
    static let detectionSeconds = 20.0

    let transcriber: ReadAlongTranscribing
    let settings: AppSettings
    let preferredLanguages: () -> [String]

    /// `isCurrent` is asked after every wait; once false, nothing more is saved or detected.
    func resolve(
        url: URL,
        supported: [String],
        source: ReadAlongAudioSource?,
        at time: Double,
        isCurrent: () -> Bool
    ) async -> Outcome {
        if let stored = settings.readAlongLanguage(for: url) {
            guard Self.isBareCode(stored) else { return .resolved(stored) }
            let installed = await transcriber.installedLocales()
            guard isCurrent() else { return .cancelled }
            guard let locale = ReadAlongLanguage.locale(
                forLanguageCode: stored,
                in: supported,
                installed: installed,
                preferredRegion: preferredRegion(for: stored)
            ) else { return .resolved(stored) }
            settings.setReadAlongLanguage(locale, for: url)
            return .resolved(locale)
        }

        guard let source, source.isOnDevice(at: time) else { return .audioMissing }
        let installed = await transcriber.installedLocales()
        guard isCurrent() else { return .cancelled }
        let candidates = ReadAlongLanguage.candidates(
            appLanguage: settings.language.languageCode,
            preferred: preferredLanguages(),
            installed: installed
        )
        var scores: [String: Double] = [:]
        for candidate in candidates {
            // A locale the engine can't score (its model isn't usable) just has no score.
            let score = try? await transcriber.confidence(
                source,
                from: time,
                seconds: Self.detectionSeconds,
                locale: candidate
            )
            guard isCurrent() else { return .cancelled }
            scores[candidate] = score
        }
        let locale = ReadAlongLanguage.best(scores) ?? appLanguageLocale(in: supported, installed: installed)
        settings.setReadAlongLanguage(locale, for: url)
        return .resolved(locale)
    }

    /// The in-app language's locale among the supported ones, chosen as `ReadAlongLanguage.locale`
    /// does (the device's region, an installed model, the likely region); the language id itself
    /// (which the model check then reports as unsupported) when iOS has none.
    private func appLanguageLocale(in supported: [String], installed: [String]) -> String {
        let id = settings.language.languageCode ?? AbbayBundle.locale.identifier
        let language = Locale(identifier: id).language
        let code = language.languageCode?.identifier ?? "en"
        let region = language.region?.identifier ?? preferredRegion(for: code)
        let locale = ReadAlongLanguage.locale(
            forLanguageCode: code,
            in: supported,
            installed: installed,
            preferredRegion: region
        )
        return locale ?? id.replacingOccurrences(of: "_", with: "-")
    }

    /// The region of the first device language in `code`: "pt" on a Brazilian device is "BR".
    private func preferredRegion(for code: String) -> String? {
        preferredLanguages().lazy
            .map { Locale(identifier: $0).language }
            .first { $0.languageCode?.identifier == code.lowercased() && $0.region != nil }?
            .region?.identifier
    }

    private static func isBareCode(_ id: String) -> Bool {
        !id.contains("-") && !id.contains("_")
    }
}

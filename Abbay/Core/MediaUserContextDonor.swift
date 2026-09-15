//
//  MediaUserContextDonor.swift
//  Abbay
//

import Intents

/// Publishes Abbay's media-app affinity signal to Siri.
///
/// `INMediaUserContext` is how a third-party media app tells the system it is a
/// real media provider with a library worth routing to. Siri's media domain uses
/// it (together with `INPlayMediaIntent` donations) to decide which app should
/// answer "play …" requests. Without a current media user context, Siri keeps
/// preferring whichever media app it already learned, which is what made
/// "Hey Siri, play <book> in Abbay" land on another app.
///
/// `becomeCurrent()` is unavailable inside app extensions, so this type lives in
/// the app target only and is driven from the app lifecycle.
protocol MediaUserContextDonorProtocol {
    func donate(libraryItemCount: Int)
}

final class MediaUserContextDonor: MediaUserContextDonorProtocol {
    // `var` so tests can rebind.
    static var shared: MediaUserContextDonorProtocol = MediaUserContextDonor()

    func donate(libraryItemCount: Int) {
        let context = makeContext(libraryItemCount: libraryItemCount)
        context.becomeCurrent()
    }

    /// Exposed for tests — `becomeCurrent()` has no observable return value.
    func makeContext(libraryItemCount: Int) -> INMediaUserContext {
        let context = INMediaUserContext()
        context.numberOfLibraryItems = libraryItemCount
        // Abbay plays the user's own files. There is no subscription to report.
        context.subscriptionStatus = .unknown
        return context
    }
}

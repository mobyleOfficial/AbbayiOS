//
//  SiriContextRefresher.swift
//  Abbay
//

import Foundation

/// Why Siri's context is being re-published, for the log.
enum SiriRefreshReason: String {
    case foreground
    case pause
    case backgroundTask
}

/// Re-publishes the library to Siri (`SiriLibraryPublisher.publish`) beyond cold launch and
/// library changes (#127).
///
/// Siri's media-app selection appears to weigh how fresh an app's signals are: plain "play <book>"
/// went straight to Abbay only when it had run recently (see
/// `docs/superpowers/research/2026-10-23-siri-app-selection.md`). Foreground and pause go through
/// `refreshIfDue`, at most once per `minimumInterval`, so a busy session doesn't spam the system.
/// The daily background task uses `refreshNow`. An experiment, judged on a device, not by tests.
protocol SiriContextRefreshing: AnyObject {
    /// Publishes unless the last publish was less than `minimumInterval` ago.
    func refreshIfDue(_ reason: SiriRefreshReason)
    /// Publishes regardless of the throttle, and restarts it.
    func refreshNow(_ reason: SiriRefreshReason)
    /// Records a publish made elsewhere (launch's snapshot write), so the first foreground after
    /// it doesn't publish again.
    func markPublished()
}

/// For players and tests that don't refresh Siri.
final class NoopSiriContextRefresher: SiriContextRefreshing {
    func refreshIfDue(_ reason: SiriRefreshReason) {}
    func refreshNow(_ reason: SiriRefreshReason) {}
    func markPublished() {}
}

final class SiriContextRefresher: SiriContextRefreshing {
    static let minimumInterval: TimeInterval = 10 * 60

    private let publisher: SiriLibraryPublisherProtocol
    private let loadAllAudios: LoadAllAudiosUseCaseProtocol
    private let now: () -> Date
    /// In memory only: a relaunch publishes anyway, so there is nothing worth persisting.
    private var lastPublish: Date?

    init(
        publisher: SiriLibraryPublisherProtocol = SiriLibraryPublisher.shared,
        loadAllAudios: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
        now: @escaping () -> Date = Date.init
    ) {
        self.publisher = publisher
        self.loadAllAudios = loadAllAudios
        self.now = now
    }

    func refreshIfDue(_ reason: SiriRefreshReason) {
        if let lastPublish, now().timeIntervalSince(lastPublish) < Self.minimumInterval {
            Log.siri.debug("context refresh skipped (\(reason.rawValue, privacy: .public)): throttled")
            return
        }
        refreshNow(reason)
    }

    func refreshNow(_ reason: SiriRefreshReason) {
        let audios = loadAllAudios.execute()
        Log.siri.info("context refresh (\(reason.rawValue, privacy: .public)): \(audios.count, privacy: .public) books")
        publisher.publish(audios: audios)
        markPublished()
    }

    func markPublished() {
        lastPublish = now()
    }
}

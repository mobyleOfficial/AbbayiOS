//
//  SiriBackgroundRefresh.swift
//  Abbay
//

import BackgroundTasks
import Foundation

/// The part of a `BGAppRefreshTask` the refresh uses, so tests can run one.
protocol BackgroundRefreshTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }

    func setTaskCompleted(success: Bool)
}

extension BGAppRefreshTask: BackgroundRefreshTask {}

/// The part of `BGTaskScheduler` the refresh uses.
protocol BackgroundRefreshScheduling {
    /// Must run before the app finishes launching. The handler runs on the main queue.
    func register(identifier: String, launchHandler: @escaping (BackgroundRefreshTask) -> Void)
    func submit(identifier: String, earliestBeginDate: Date) throws
}

struct SystemBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    /// `BGTaskScheduler` raises an exception on a second registration of an identifier, and the
    /// unit tests launch the app delegate more than once in one process.
    private static var registered: Set<String> = []

    var log: SiriLogSink = OSSiriLogSink()

    func register(identifier: String, launchHandler: @escaping (BackgroundRefreshTask) -> Void) {
        guard Self.registered.insert(identifier).inserted else { return }
        // The main queue: the publish reads Core Data through the view context.
        let didRegister = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            launchHandler(task)
        }
        if !didRegister {
            log.log(.backgroundRefreshRegistrationRefused(identifier: identifier))
        }
    }

    func submit(identifier: String, earliestBeginDate: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }
}

/// A daily `BGAppRefreshTask` that re-publishes Siri's context while the app isn't used (#127).
///
/// The complaint it aims at is a stale context after hours without opening the app, when plain
/// "play <book>" makes Siri ask which app to use. iOS decides when, or whether, it runs, based on
/// usage; whether it helps Siri is the experiment. If it shows no improvement on a device, drop it
/// (it costs battery and review surface).
///
/// Registered at launch, scheduled each time the app goes to the background (a new request
/// replaces the pending one), and rescheduled by every run.
final class SiriBackgroundRefresh {
    /// Also listed in `BGTaskSchedulerPermittedIdentifiers` (Info.plist).
    static let identifier = "com.edyuto.Abbay.siriRefresh"
    static let interval: TimeInterval = 24 * 60 * 60

    private let scheduler: BackgroundRefreshScheduling
    private let refresher: SiriContextRefreshing
    private let now: () -> Date
    private let log: SiriLogSink

    init(
        scheduler: BackgroundRefreshScheduling = SystemBackgroundRefreshScheduler(),
        refresher: SiriContextRefreshing,
        now: @escaping () -> Date = Date.init,
        log: SiriLogSink = OSSiriLogSink()
    ) {
        self.scheduler = scheduler
        self.refresher = refresher
        self.now = now
        self.log = log
    }

    func register() {
        scheduler.register(identifier: Self.identifier) { [weak self] task in
            self?.handle(task)
        }
    }

    func schedule() {
        do {
            let earliestBeginDate = now().addingTimeInterval(Self.interval)
            try scheduler.submit(identifier: Self.identifier, earliestBeginDate: earliestBeginDate)
        } catch {
            // Expected on the simulator, and when the user turned Background App Refresh off.
            log.log(.backgroundRefreshNotScheduled(error as NSError))
        }
    }

    /// Internal for tests. Completes the task exactly once, when the publish reports it has
    /// finished (Spotlight indexing included, #159), or unsuccessfully if the system expires it
    /// first. The lock because the expiration handler can run on another thread than the publish's
    /// completion.
    func handle(_ task: BackgroundRefreshTask) {
        schedule()
        let log = self.log
        let lock = NSLock()
        var isCompleted = false
        let complete = { (success: Bool) in
            let isFirst = lock.withLock {
                defer { isCompleted = true }
                return !isCompleted
            }
            guard isFirst else { return }
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            log.log(.backgroundRefreshExpired)
            complete(false)
        }
        refresher.refreshNow(.backgroundTask) {
            log.log(.backgroundRefreshPublishFinished)
            complete(true)
        }
    }
}

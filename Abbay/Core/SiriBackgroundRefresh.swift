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
            Log.siri.error("background refresh: registration refused for \(identifier, privacy: .public)")
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

    init(
        scheduler: BackgroundRefreshScheduling = SystemBackgroundRefreshScheduler(),
        refresher: SiriContextRefreshing,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.refresher = refresher
        self.now = now
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
            let error = error as NSError
            Log.siri.error("background refresh: not scheduled: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        }
    }

    /// Internal for tests. Completes the task exactly once: unsuccessfully if the system expires it
    /// first. The publish itself is synchronous; the Spotlight and App Shortcut work it starts
    /// finishes on the system's side. The lock because the expiration handler can run on another
    /// thread while the publish runs on main.
    func handle(_ task: BackgroundRefreshTask) {
        schedule()
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
            Log.siri.info("background refresh: expired")
            complete(false)
        }
        refresher.refreshNow(.backgroundTask)
        complete(true)
    }
}

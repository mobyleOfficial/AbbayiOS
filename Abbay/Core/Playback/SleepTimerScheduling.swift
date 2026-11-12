//
//  SleepTimerScheduling.swift
//  Abbay
//

import Combine
import Foundation

/// The sleep timer's clock (#332): a monotonic `now` in seconds, and work run after a delay.
/// Injected so the timer's tests move time by hand.
@MainActor
protocol SleepTimerScheduling {
    var now: TimeInterval { get }
    /// Runs `work` on the main actor after `seconds`, unless the returned token is cancelled or
    /// released first.
    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> AnyCancellable
}

/// The app's clock: `ContinuousClock`, which keeps counting while the screen is locked. While a book
/// plays, the audio background mode keeps the process running, so the sleeps wake on time.
@MainActor
struct TaskSleepTimerScheduler: SleepTimerScheduling {
    private let origin: ContinuousClock.Instant

    /// `nonisolated` so it can be a default argument.
    nonisolated init() {
        origin = .now
    }

    var now: TimeInterval {
        let elapsed = origin.duration(to: .now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> AnyCancellable {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(seconds, 0)))
            guard !Task.isCancelled else { return }
            work()
        }
        return AnyCancellable { task.cancel() }
    }
}

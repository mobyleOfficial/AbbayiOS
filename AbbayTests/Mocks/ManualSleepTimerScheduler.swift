//
//  ManualSleepTimerScheduler.swift
//  AbbayTests
//

@testable import Abbay
import Combine
import Foundation

/// A clock the sleep timer's tests move by hand: `advance(by:)` runs every piece of work that
/// falls due, in time order (and work scheduled while advancing, if it falls due too).
@MainActor
final class ManualSleepTimerScheduler: SleepTimerScheduling {
    private struct Item {
        let id: Int
        let due: TimeInterval
        let work: @MainActor () -> Void
    }

    private(set) var now: TimeInterval = 0
    private var items: [Item] = []
    private var nextID = 0

    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> AnyCancellable {
        let id = nextID
        nextID += 1
        items.append(Item(id: id, due: now + max(seconds, 0), work: work))
        return AnyCancellable { [weak self] in
            MainActor.assumeIsolated { self?.items.removeAll { $0.id == id } }
        }
    }

    func advance(by seconds: TimeInterval) {
        let end = now + seconds
        while let next = items.filter({ $0.due <= end }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) {
            items.removeAll { $0.id == next.id }
            now = next.due
            next.work()
        }
        now = end
    }
}

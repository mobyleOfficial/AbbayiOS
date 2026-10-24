//
//  SiriDiagnostics.swift
//  Abbay
//

import Foundation

/// A small ring buffer in the App Group so Siri behaviour can be inspected after
/// the fact without root access to the device's unified log.
///
/// The app records its Siri authorization status at launch; the extension records
/// every decision it makes. If a spoken request goes somewhere else and no
/// extension entry appears, Siri never consulted us — which separates a routing
/// problem from a decision problem.
///
/// Nothing here records what the user said. Only outcome labels and whether the
/// request carried a title at all.
///
/// The store is injected. The static `record` is a log call, like `os_log`: it writes to
/// `shared`, the App Group trail, so call sites with nothing to inject don't have to thread one.
struct SiriDiagnostics {
    static let key: String = "abbay.diagnostics.v1"
    static let limit: Int = 25

    static let shared = SiriDiagnostics()

    private let store: KeyValueStoring

    init(store: KeyValueStoring = AppGroup.store) {
        self.store = store
    }

    static func record(_ event: String, now: Date = Date()) {
        shared.record(event, now: now)
    }

    func record(_ event: String, now: Date = Date()) {
        let stamp = ISO8601DateFormatter().string(from: now)
        var events = self.events()
        events.append("\(stamp) \(event)")
        store.set(Array(events.suffix(Self.limit)), forKey: Self.key)
        // Flush immediately: this trail is read by copying the App Group container
        // off the device, and an un-flushed write is invisible there while the
        // writing process is still alive.
        store.synchronize()
    }

    func events() -> [String] {
        store.object(forKey: Self.key) as? [String] ?? []
    }

    func clear() {
        store.removeObject(forKey: Self.key)
    }
}

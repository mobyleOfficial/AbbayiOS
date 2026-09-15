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
enum SiriDiagnostics {
    static let key: String = "abbay.diagnostics.v1"
    static let limit: Int = 25

    // `var` so tests can rebind.
    static var defaults: UserDefaults = AppGroup.defaults

    static func record(_ event: String, now: Date = Date()) {
        let stamp = ISO8601DateFormatter().string(from: now)
        var events = self.events()
        events.append("\(stamp) \(event)")
        defaults.set(Array(events.suffix(limit)), forKey: key)
        // Flush immediately: this trail is read by copying the App Group container
        // off the device, and an un-flushed write is invisible there while the
        // writing process is still alive.
        defaults.synchronize()
    }

    static func events() -> [String] {
        defaults.array(forKey: key) as? [String] ?? []
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}

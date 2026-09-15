//
//  LaunchStateFlag.swift
//  Abbay
//

import Foundation

enum LaunchStateFlag {
    static let key: String = "abbay.audioSessionUnavailable"

    // `var` so tests can rebind in setUp/tearDown
    static var defaults: UserDefaults = AppGroup.defaults

    static func markUnavailable() {
        defaults.set(true, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    static func isUnavailable() -> Bool {
        defaults.bool(forKey: key)
    }
}

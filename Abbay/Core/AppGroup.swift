//
//  AppGroup.swift
//  Abbay
//

import Foundation

enum AppGroup {
    static let suiteName: String = "group.com.edyuto.abbay"

    static let defaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("App Group \(suiteName) not configured — check entitlements")
        }
        return defaults
    }()
}

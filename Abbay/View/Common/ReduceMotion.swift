//
//  ReduceMotion.swift
//  Abbay
//

import SwiftUI

/// Reduce Motion as the app's views read it: the system setting, unless `-forceReduceMotion`
/// forces it on (Debug builds only, for UI tests). Use `@ReduceMotion private var reduceMotion`
/// instead of `@Environment(\.accessibilityReduceMotion)`; SwiftLint's
/// `reduce_motion_through_wrapper` rule enforces it.
///
/// Why not an environment override at the root (#185): on iOS 17 and 18 a `NavigationStack`
/// destination, a sheet or any other surface UIKit hosts in its own `UIHostingController`
/// re-reads the accessibility environment from the system, so a value set with
/// `.transformEnvironment(\._accessibilityReduceMotion)` on `AppRootView` stopped at the Search
/// tab's pushed details page (iOS 26 propagates it). The forced value here comes from the launch
/// arguments, not the environment, so it holds on every surface, however it is hosted.
@propertyWrapper
struct ReduceMotion: DynamicProperty {
    /// Read once: the launch arguments don't change while the app runs.
    private static let forcedAtLaunch = DebugOverrides.reduceMotion()

    @Environment(\.accessibilityReduceMotion)
    private var system
    private let forced: Bool?

    init() {
        forced = Self.forcedAtLaunch
    }

    /// For tests and previews: `forced` replaces the launch argument's value.
    init(forced: Bool?) {
        self.forced = forced
    }

    var wrappedValue: Bool {
        Self.resolve(system: system, forced: forced)
    }

    /// A forced value wins; `nil` follows the system.
    static func resolve(system: Bool, forced: Bool?) -> Bool {
        forced ?? system
    }
}

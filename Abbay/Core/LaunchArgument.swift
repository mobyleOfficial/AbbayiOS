//
//  LaunchArgument.swift
//  Abbay
//

/// Launch-argument names shared between the app and the UI test target.
///
/// Compiled into both targets, like `AccessibilityID`: a UI test bundle runs out of process and
/// cannot `import Abbay`, so sharing the source file is the only way to avoid two copies of
/// these strings drifting apart. Only the names live here -- the behaviour they trigger is in
/// `Abbay/DebugSupport/` (`DebugOverrides` and the `UITest*` stand-ins), which stays app-side
/// because it touches Core Data and is `#if DEBUG` only.
enum LaunchArgument {
    /// Replace the library with deterministic sample books.
    static let seedLibrary = "-seedLibrary"
    /// Empty the library, for asserting the empty state.
    static let resetLibrary = "-resetLibrary"
    /// Answer LibriVox requests from an in-memory stub and download nothing, instead of using the
    /// network.
    static let stubLibriVox = "-stubLibriVox"
}

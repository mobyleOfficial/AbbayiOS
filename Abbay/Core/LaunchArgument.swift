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
    /// With `seedLibrary`: also add filler books, so the list is longer than the screen.
    static let seedFillerBooks = "-seedFillerBooks"
    /// With `seedLibrary`: also add a book with 60 chapters, so the details screen's chapter list
    /// is much longer than the screen (the list-at-top collapse checks).
    static let seedLongBook = "-seedLongBook"
    /// With `seedLibrary`: also add *Seeded Playable Book*, the real four-chapter LibriVox m4b the
    /// unit tests use, 56 s into its second chapter, so chapter actions have something to move.
    static let seedPlayableBook = "-seedPlayableBook"
    /// Empty the library, for asserting the empty state.
    static let resetLibrary = "-resetLibrary"
    /// Answer LibriVox requests from an in-memory stub and download nothing, instead of using the
    /// network.
    static let stubLibriVox = "-stubLibriVox"
    /// Make *Import file* skip the system picker and import two files that don't exist, so the
    /// failed-import banner shows.
    static let stubFailingImport = "-stubFailingImport"
    /// Start from the default settings, kept in memory for this launch only, so a test that changes
    /// the language or a skip interval can't leak it into the next launch.
    static let resetSettings = "-resetSettings"
    /// Run with Reduce Motion on, whatever the system setting says: XCUITest can't switch the
    /// setting itself.
    static let forceReduceMotion = "-forceReduceMotion"
}

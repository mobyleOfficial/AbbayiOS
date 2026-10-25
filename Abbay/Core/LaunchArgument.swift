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
    /// Replace the library with deterministic sample books. Their audio is the Debug-only
    /// `Christmastide.m4b` fixture (one hard-linked copy per book), so pressing Play plays (#147).
    static let seedLibrary = "-seedLibrary"
    /// With `seedLibrary`: also add filler books, so the list is longer than the screen.
    static let seedFillerBooks = "-seedFillerBooks"
    /// With `seedLibrary`: also add a book with 60 chapters, so the details screen's chapter list
    /// is much longer than the screen (the list-at-top collapse checks).
    static let seedLongBook = "-seedLongBook"
    /// With `seedLibrary`: also add *Seeded Playable Book*, the real four-chapter LibriVox m4b the
    /// unit tests use, 56 s into its second chapter, so chapter actions have something to move.
    static let seedPlayableBook = "-seedPlayableBook"
    /// With `seedLibrary`: also add *Seeded Finished Book* (no chapters, listened to the end, so its
    /// row reads "0s left") and *Seeded Hour Book* (a first chapter exactly one hour long, so the
    /// mini player reads "1 hr left" once it is loaded): the time-left edge cases of #152.
    static let seedTimeLeftEdges = "-seedTimeLeftEdges"
    /// With `seedLibrary`: also add *Seeded Missing Book*, whose file doesn't exist, which is what a
    /// moved or renamed import looks like: Play shows the moved-file banner (#139, #147).
    static let seedMissingFile = "-seedMissingFile"
    /// Empty the library, for asserting the empty state.
    static let resetLibrary = "-resetLibrary"
    /// Answer LibriVox requests from an in-memory stub and download nothing, instead of using the
    /// network.
    static let stubLibriVox = "-stubLibriVox"
    /// With `stubLibriVox`: give the stub book an archive.org cover that an in-memory network
    /// answers after a few seconds, so the cover's loading and loaded states can be seen. The
    /// covers' disk cache is a separate one, emptied at launch.
    static let stubCovers = "-stubCovers"
    /// With `stubCovers`: every cover request fails and the stub covers' disk cache is kept, so a
    /// cover can only come from disk (what an earlier `stubCovers` launch stored).
    static let stubCoversOffline = "-stubCoversOffline"
    /// Make *Import file* skip the system picker and import two files that don't exist, so the
    /// failed-import banner shows.
    static let stubFailingImport = "-stubFailingImport"
    /// Start from the default settings, kept in memory for this launch only, so a test that changes
    /// the language or a skip interval can't leak it into the next launch.
    static let resetSettings = "-resetSettings"
    /// Run with Reduce Motion on, whatever the system setting says: XCUITest can't switch the
    /// setting itself.
    static let forceReduceMotion = "-forceReduceMotion"

    /// Every name above. A launch carrying any of them is a UI test's.
    static let all = [
        seedLibrary, seedFillerBooks, seedLongBook, seedPlayableBook, seedTimeLeftEdges, seedMissingFile,
        resetLibrary, stubLibriVox, stubCovers, stubCoversOffline, stubFailingImport, resetSettings,
        forceReduceMotion
    ]
}

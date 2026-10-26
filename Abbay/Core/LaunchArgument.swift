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
    /// With `seedLibrary`: give *Seeded Chaptered Book* and *Seeded Playable Book* a generated
    /// cover (a warm gradient), so the cover tint behind the mini player and the details screen
    /// (#166 G1) can be seen. *Seeded Plain Book* keeps none, for the generic tile.
    static let seedCoverArt = "-seedCoverArt"
    /// With `seedLibrary`: give *Seeded Chaptered Book*, *Seeded Playable Book* and *Seeded Long
    /// Book* generated covers (a gradient with the title), so a library shows covers next to books
    /// without artwork. *Seeded Plain Book* and the filler books keep none.
    static let seedArtwork = "-seedArtwork"
    /// With `seedLibrary`: make the first seeded book (*Seeded Chaptered Book*, 150 s in) the last
    /// played one, so the library's Continue card shows it. Without it, seeding clears last played,
    /// so no Continue card is left over from an earlier launch.
    static let seedLastPlayed = "-seedLastPlayed"
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
    /// With `stubLibriVox`: a book's details arrive in two steps, like a slow LibriVox (#258).
    /// "archive.org" answers after `UITestLibriVoxClient.archiveDelay` with file-name chapter titles
    /// and no description, "LibriVox" `libriVoxDelay` later with the real ones; meanwhile the page
    /// shimmers.
    static let stubSlowLibriVox = "-stubSlowLibriVox"
    /// With `stubLibriVox`: the stub book has three chapters, 120 MB in all (over the cellular
    /// threshold), and the stub download manager publishes a state for every book it is given
    /// (first chapter downloaded, last failed, the rest waiting), so the download status ids can
    /// be reached.
    static let stubDownloadStates = "-stubDownloadStates"
    /// The network path is cellular, whatever the Mac's network is.
    static let stubPathCellular = "-stubPathCellular"
    /// The network path is a Personal Hotspot: Wi-Fi that is expensive.
    static let stubPathHotspot = "-stubPathHotspot"
    /// The network path is Wi-Fi in Low Data Mode.
    static let stubPathLowDataMode = "-stubPathLowDataMode"
    /// The network path is offline, whatever the Mac's network is: the Search tab's offline state.
    static let stubPathOffline = "-stubPathOffline"
    /// Make *Import file* skip the system picker and import two files that don't exist, so the
    /// failed-import banner shows.
    static let stubFailingImport = "-stubFailingImport"
    /// Make *Import file* skip the system picker and import *Seeded Missing Book*'s file from where
    /// it "moved" to (`UITestSeedAudio/moved/missing.m4b`, the fixture's audio), which is what the
    /// moved-file banner asks for: with `seedMissingFile`, the book is relinked, not added (#196).
    static let stubMovedImport = "-stubMovedImport"
    /// Start from the default settings, kept in memory for this launch only, so a test that changes
    /// the language or a skip interval can't leak it into the next launch.
    static let resetSettings = "-resetSettings"
    /// Run with Reduce Motion on, whatever the system setting says: XCUITest can't switch the
    /// setting itself.
    static let forceReduceMotion = "-forceReduceMotion"

    /// Every name above. A launch carrying any of them is a UI test's.
    static let all = [
        seedLibrary, seedFillerBooks, seedLongBook, seedPlayableBook, seedTimeLeftEdges, seedMissingFile,
        seedCoverArt, seedArtwork, seedLastPlayed, resetLibrary, stubLibriVox, stubCovers, stubCoversOffline,
        stubSlowLibriVox,
        stubDownloadStates, stubPathCellular, stubPathHotspot, stubPathLowDataMode, stubPathOffline,
        stubFailingImport, stubMovedImport, resetSettings, forceReduceMotion
    ]
}

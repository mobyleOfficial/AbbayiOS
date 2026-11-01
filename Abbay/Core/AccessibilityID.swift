//
//  AccessibilityID.swift
//  Abbay
//

/// Accessibility identifiers for the elements a UI driver needs to reach.
///
/// Convention: `<screen>.<element>[.<qualifier>]`, matching
/// `.claude/skills/verify-abbay/features/`. This file is compiled into **both** the app and the
/// UI test target -- UI tests run out of process and cannot import the app module, so a shared
/// source file is the only way to keep one source of truth.
///
/// Nesting stops at two type levels (SwiftLint `nesting: type_level: 2`), so per-element
/// suffixes are functions over a namespace rather than a third nested type.
///
/// **Identifiers go on leaves, never on containers that hold other identified elements.**
/// SwiftUI applies `.accessibilityIdentifier` to every accessibility element in the subtree, so
/// an identifier on a container silently overwrites its children's. That is why there is no
/// `library.root` or `player.root` here: both clobbered everything beneath them. Use
/// `library.list` / `library.empty` and a specific player control as the "screen is up" signal.
/// Verified by `AbbayUITests/AccessibilityIdentifierTests`.
///
/// Scope note: this covers the tabs, the library, the row, the mini player and the player. The
/// mini player appears once a book is loaded, which the seeded and stub books reach without
/// playable audio.
enum AccessibilityID {
    /// The root tab bar's items: the system tab bar on iOS 26.1+, the hand-built one before.
    enum Root {
        static let tabLibrary = "root.tab.library"
        static let tabSearch = "root.tab.search"
    }

    enum Library {
        static let list = "library.list"
        static let empty = "library.empty"
        static let toolbarAdd = "library.toolbar.add"
        static let menuImport = "library.menu.import"
        static let menuDownload = "library.add.download"
        static let emptyBrowse = "library.empty.browse"
        static let emptyImport = "library.empty.import"
        static let noResults = "library.search.noResults"
        static let toolbarSettings = "library.toolbar.settings"
        /// The Continue card's title (the last played book): taps open the player. A leaf; the
        /// card itself has no identifier.
        static let continueTitle = "library.continue"
        /// The card's "Chapter 3 · 28 min left".
        static let continueDetail = "library.continue.detail"
        /// The card's Resume / Pause capsule.
        static let continueResume = "library.continue.resume"

        /// Namespace for one library grid cell. Kept as `row` from the list it replaced (#166 G3), so
        /// `library.row.N.title` etc. still address the Nth book. Positional: read a snapshot, then
        /// address by index.
        static func row(_ index: Int) -> String {
            "library.row.\(index)"
        }
    }

    /// The app-wide error banner (`NoticeBannerView`), above every screen.
    enum Notice {
        static let banner = "notice.banner"
    }

    /// The one-row mini player, docked above the tabs.
    enum MiniPlayer {
        /// The title and subtitle: one element that taps open the details screen and carries the
        /// open / next chapter / restart chapter actions. A leaf, not the bar's container.
        static let bar = "miniPlayer.bar"
        static let playPause = "miniPlayer.playPause"
        static let progress = "miniPlayer.progress"
    }

    enum Search {
        static let message = "search.message"
        static let noResults = "search.noResults"

        static func card(_ index: Int) -> String {
            "search.card.\(index)"
        }

        static func result(_ index: Int) -> String {
            "search.result.\(index)"
        }
    }

    /// A remote cover (`AsyncImageView`), by load state. Verified on the details page; inside a
    /// search card or result the button keeps its own id.
    enum Cover {
        static let loading = "cover.loading"
        static let loaded = "cover.loaded"
        static let failed = "cover.failed"
    }

    enum Detail {
        static let view = "detail.view"
        static let download = "detail.download"
        static let play = "detail.play"
        /// The compact Download in the navigation bar, once `download` has scrolled away (#166 G5).
        static let pinnedDownload = "detail.pinned.download"
        /// The compact Play in the navigation bar, once `play` has scrolled away.
        static let pinnedPlay = "detail.pinned.play"
        static let more = "detail.more"
        static let retry = "detail.retry"
        static let progress = "detail.progress"
        /// "Waiting: Low Data Mode is on" under the progress bar, for a Wait-for-Wi-Fi book held by it.
        static let lowDataMode = "detail.lowDataMode"
        /// "Waiting for Wi-Fi: on cellular", the same place, for one held on cellular data.
        static let cellularHold = "detail.cellularHold"
        /// "Waiting for Wi-Fi: on a Personal Hotspot", the same place, for one held on a hotspot.
        static let hotspotHold = "detail.hotspotHold"
        static let chaptersEmpty = "detail.chapters.empty"
        /// The shimmering description while LibriVox's is on its way (#258).
        static let descriptionLoading = "detail.description.loading"
        /// The shimmering "3h 5min · 12 chapters · 296.7 MB" line before archive.org has answered.
        static let metadataLoading = "detail.metadata.loading"
        /// The chapter card of shimmering rows before archive.org has answered.
        static let chaptersLoading = "detail.chapters.loading"
        static let cellularContinue = "detail.cellular.continue"
        static let cellularWait = "detail.cellular.wait"

        static func chapter(_ index: Int) -> String {
            "detail.chapter.\(index)"
        }

        /// A failed chapter's "Failed · Retry" status button.
        static func chapterRetry(_ index: Int) -> String {
            "detail.chapter.\(index).retry"
        }

        /// A chapter's shimmering title, while LibriVox's titles are on their way (#258).
        static func chapterTitleLoading(_ index: Int) -> String {
            "detail.chapter.\(index).titleLoading"
        }
    }

    /// The Settings sheet, opened by `library.toolbar.settings`. `settings.done` is the "screen is
    /// up" signal (there is no `settings.root`, per the leaf rule).
    enum Settings {
        static let done = "settings.done"
        static let defaultSpeed = "settings.playback.defaultSpeed"
        static let skipBack = "settings.playback.skipBack"
        static let skipForward = "settings.playback.skipForward"
        static let cellular = "settings.downloads.cellular"
        static let spaceUsed = "settings.downloads.spaceUsed"
        static let deleteFinished = "settings.downloads.deleteFinished"
        static let deleteConfirm = "settings.downloads.deleteConfirm"
        static let deleteCancel = "settings.downloads.deleteCancel"
        static let privacyPolicy = "settings.about.privacyPolicy"
        static let version = "settings.about.version"
        static let librivox = "settings.about.librivox"
        static let licenses = "settings.about.licenses"
        static let licensesBody = "settings.about.licenses.body"
        static let audioStatus = "settings.about.audioStatus"
        static let developer = "settings.about.developer"
        static let developerBody = "settings.about.developer.body"
        static let linkedIn = "settings.about.linkedIn"
        /// The Experimental section's Read-along switch (iOS 26 and later only).
        static let readAlong = "settings.experimental.readAlong"

        /// One option of the language picker; `language` is an `AppLanguage` raw value.
        static func language(_ language: String) -> String {
            "settings.language.\(language)"
        }
    }

    /// The speed control: in the player's speed sheet, and on Settings' default speed page.
    enum Speed {
        static let value = "speed.value"
        static let decrease = "speed.decrease"
        static let increase = "speed.increase"
        static let slider = "speed.slider"
        static let setDefault = "speed.setDefault"

        /// A preset chip, by its speed: `speed.preset.1.5`.
        static func preset(_ speed: Double) -> String {
            "speed.preset.\(speed)"
        }
    }

    enum Player {
        /// Closes the details screen (the chevron in its header; the header also drags down).
        static let close = "player.close"
        /// Opens the speed sheet; its label is the book's speed ("1.5×").
        static let speed = "player.speed"
        /// The volume pill beside the speed: opens the volume capsule (and closes it). Its label is
        /// "Book volume", its value the level ("60%"); VoiceOver adjusts it in place.
        static let volume = "player.volume"
        /// The open volume capsule above the pill: an adjustable slider, Abbay's own volume.
        static let volumeSlider = "player.volume.slider"
        /// The header strip at the top of the details screen (it no longer draws a grabber bar):
        /// drag it down to collapse into the bar.
        /// Hidden from accessibility, so XCUITest can't resolve it; drag from beside `close`.
        static let grabber = "player.grabber"
        static let title = "player.title"
        /// The chapter panel's "Chapters" header (#166 G2).
        static let chaptersTitle = "player.chapters.title"
        /// The Chapters pill: opens the chapter panel, and closes it (✕) while open. Absent for a
        /// book with no chapters.
        static let chapters = "player.chapters"
        /// The open chapter panel's handle at its top (a leaf): VoiceOver's "Close chapters", and
        /// where a drag down closes the panel.
        static let chaptersPanel = "player.chapters.panel"
        /// The chapter name under the scrubber, a menu button (#299). Its one item
        /// (`restartChapter`) plays the chapter shown from its beginning.
        static let chapterMenu = "player.chapterMenu"
        static let restartChapter = "player.restartChapter"
        static let downloadProgress = "player.download.progress"
        /// "Waiting: Low Data Mode is on" under the progress bar, for a Wait-for-Wi-Fi book held by it.
        static let downloadLowDataMode = "player.download.lowDataMode"
        /// "Waiting for Wi-Fi: on cellular", the same place, for one held on cellular data.
        static let downloadCellularHold = "player.download.cellularHold"
        /// "Waiting for Wi-Fi: on a Personal Hotspot", the same place, for one held on a hotspot.
        static let downloadHotspotHold = "player.download.hotspotHold"
        /// The Text pill (read-along, #192): flips the cover square to the text and back. Present
        /// only while Read-along is on (iOS 26+).
        static let text = "player.text"
        /// The read-along square, in the cover's place while the Text pill is on.
        static let readAlong = "player.readAlong"
        /// The square's language label (*English ▾*): a menu of the languages iOS can transcribe.
        static let readAlongLanguage = "player.readAlong.language"
        /// The square's message while there is no text to show (preparing, no audio, no speech…).
        static let readAlongStatus = "player.readAlong.status"
        /// The square's expand button (bottom-right, opposite the language label): the text goes
        /// full screen. Hidden while the chapter panel is open, like the language label.
        static let readAlongExpand = "player.readAlong.expand"
        /// The full-screen text, over the whole window (both panes when split).
        static let readAlongFullScreen = "player.readAlong.fullScreen"
        /// The full-screen text's collapse button (bottom-right): back to the square.
        static let readAlongCollapse = "player.readAlong.collapse"
        /// The full-screen text's play/pause button (bottom-centre); its label is *Play* or *Pause*.
        static let readAlongPlayPause = "player.readAlong.playPause"

        /// A line of the read-along text, by its position in the transcript; the current one carries
        /// the selected trait.
        static func readAlongLine(_ index: Int) -> String {
            "player.readAlong.line.\(index)"
        }

        static func chapter(_ index: Int) -> String {
            "player.chapter.\(index)"
        }

        /// A failed chapter's "Failed · Retry" status button.
        static func chapterRetry(_ index: Int) -> String {
            "player.chapter.\(index).retry"
        }

        /// `control` is one of the `Transport` constants.
        static func transport(_ control: String) -> String {
            "player.transport.\(control)"
        }
    }

    /// Suffixes derived from an owner's namespace, so one component can appear on several
    /// screens without colliding.
    enum Element {
        static func artwork(_ namespace: String) -> String {
            "\(namespace).artwork"
        }

        static func title(_ namespace: String) -> String {
            "\(namespace).title"
        }

        /// A library cell's context-menu Play / Pause item (the menu exists only while it is open).
        static func play(_ namespace: String) -> String {
            "\(namespace).play"
        }

        /// A library cell's context-menu Delete item.
        static func delete(_ namespace: String) -> String {
            "\(namespace).delete"
        }

        /// A library cell's status line: New, Ch N/M, the time left, or Finished.
        static func detail(_ namespace: String) -> String {
            "\(namespace).detail"
        }

        static func downloadRing(_ namespace: String) -> String {
            "\(namespace).downloadRing"
        }
    }

    /// The back and forward skips jump by the Settings amounts, so their identifiers carry no number.
    enum Transport {
        static let back = "back"
        static let play = "play"
        static let forward = "forward"
    }
}

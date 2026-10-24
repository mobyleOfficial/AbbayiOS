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
        static let emptyBrowse = "library.empty.browse"
        static let emptyImport = "library.empty.import"
        static let noResults = "library.search.noResults"
        static let toolbarSettings = "library.toolbar.settings"

        /// Namespace for one library row. Positional: read a snapshot, then address by index.
        static func row(_ index: Int) -> String {
            "library.row.\(index)"
        }
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

    enum Detail {
        static let view = "detail.view"
        static let download = "detail.download"
        static let play = "detail.play"
        static let more = "detail.more"
        static let retry = "detail.retry"
        static let progress = "detail.progress"
        static let cellularContinue = "detail.cellular.continue"
        static let cellularWait = "detail.cellular.wait"

        static func chapter(_ index: Int) -> String {
            "detail.chapter.\(index)"
        }

        /// A failed chapter's "Failed · Retry" status button.
        static func chapterRetry(_ index: Int) -> String {
            "detail.chapter.\(index).retry"
        }
    }

    enum Player {
        /// Closes the details screen (the chevron in its header; the header also drags down).
        static let close = "player.close"
        /// The grabber at the top of the details screen: drag it down to collapse into the bar.
        static let grabber = "player.grabber"
        static let title = "player.title"
        static let chaptersTitle = "player.chapters.title"
        static let downloadProgress = "player.download.progress"

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

        static func play(_ namespace: String) -> String {
            "\(namespace).play"
        }

        /// A row's one line of detail: author plus chapter N/M, or time left.
        static func detail(_ namespace: String) -> String {
            "\(namespace).detail"
        }

        static func downloadRing(_ namespace: String) -> String {
            "\(namespace).downloadRing"
        }
    }

    enum Transport {
        static let back30 = "back30"
        static let back15 = "back15"
        static let play = "play"
        static let forward15 = "forward15"
        static let forward30 = "forward30"
    }
}

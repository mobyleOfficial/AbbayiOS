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
/// Scope note: this covers the library, the row and the player -- everything a driver can reach
/// without working playback. The floating player's internals and the progress labels are not
/// here yet, because the floating player only appears once audio is actually playing and that
/// needs the seeded fixture to be playable.
enum AccessibilityID {
    enum Library {
        static let list = "library.list"
        static let empty = "library.empty"
        static let toolbarAdd = "library.toolbar.add"
        static let menuBrowse = "library.menu.browse"
        static let menuImport = "library.menu.import"
        static let emptyBrowse = "library.empty.browse"
        static let emptyImport = "library.empty.import"
        static let noResults = "library.search.noResults"
        static let searchMessage = "library.search.message"
        static let toolbarSettings = "library.toolbar.settings"
        static let floatingPlayer = "library.floatingPlayer"

        /// Namespace for one LibriVox search result, positional within the "On LibriVox" section.
        static func remoteRow(_ index: Int) -> String {
            "library.remote.\(index)"
        }

        /// Namespace for one local search match, positional within "In your library".
        static func localRow(_ index: Int) -> String {
            "library.search.local.\(index)"
        }

        /// Namespace for one library row. Positional: read a snapshot, then address by index.
        static func row(_ index: Int) -> String {
            "library.row.\(index)"
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
    }

    enum Player {
        static let title = "player.title"
        static let chaptersTitle = "player.chapters.title"
        static let downloadProgress = "player.download.progress"

        static func chapter(_ index: Int) -> String {
            "player.chapter.\(index)"
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

        static func chapterCount(_ namespace: String) -> String {
            "\(namespace).chapterCount"
        }

        static func timestamp(_ namespace: String) -> String {
            "\(namespace).timestamp"
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

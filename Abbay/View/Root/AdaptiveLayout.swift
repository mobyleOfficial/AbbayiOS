//
//  AdaptiveLayout.swift
//  Abbay
//

import SwiftUI

/// How the window is split (#255): one pane, or browsing beside a player pane. Decided from the
/// room the app is given and the text size, never from the device model, so a regular iPhone, both
/// iPhone Duo displays and an iPad window of any size follow the same rules.
enum PaneLayout: Equatable {
    /// One pane: the player covers browsing, and the chapters float over the player.
    case single
    /// Browsing (or the chapters) beside a player pane `playerWidth` wide.
    case split(playerWidth: CGFloat)

    var isSplit: Bool {
        if case .split = self { return true }
        return false
    }

    var playerWidth: CGFloat? {
        if case let .split(width) = self { return width }
        return nil
    }
}

/// The pure decision, so it is unit tested. The minimums are what each pane needs to read well:
/// browsing keeps a grid of at least three covers, and the player keeps its transport, scrubber
/// and pills on one line with a cover worth showing.
enum AdaptiveLayout {
    /// Browsing's least width: three covers with their titles, or the search results' rows.
    static let minBrowsingWidth: CGFloat = 360
    /// The player pane's least and largest width. Wider than that, the extra room is browsing's.
    static let minPlayerWidth: CGFloat = 360
    static let maxPlayerWidth: CGFloat = 460
    /// The player pane's share of the width, between those two.
    static let playerShare: CGFloat = 0.42
    /// Below this height the player's cover would shrink to a thumbnail beside a grid: one pane.
    static let minSplitHeight: CGFloat = 500

    /// `width` and `height` are the space the app's content is given (inside the safe area).
    /// A compact width is always one pane; a regular one is split when both panes fit at this
    /// text size. Accessibility text sizes need more room for both.
    static func decide(
        width: CGFloat,
        height: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass?,
        dynamicTypeSize: DynamicTypeSize
    ) -> PaneLayout {
        guard horizontalSizeClass == .regular else { return .single }
        let scale = textScale(dynamicTypeSize)
        let minPlayer = minPlayerWidth * scale
        let minBrowsing = minBrowsingWidth * scale
        guard height >= minSplitHeight, width >= minPlayer + minBrowsing else { return .single }
        let player = min(max(width * playerShare, minPlayer), max(maxPlayerWidth, minPlayer))
        guard width - player >= minBrowsing else { return .single }
        return .split(playerWidth: player.rounded())
    }

    /// How much more room both panes need at this text size.
    static func textScale(_ size: DynamicTypeSize) -> CGFloat {
        if size.isAccessibilitySize { return 1.4 }
        if size >= .xLarge { return 1.15 }
        return 1
    }
}

// MARK: - Environment

private struct PaneLayoutKey: EnvironmentKey {
    static let defaultValue: PaneLayout = .single
}

extension EnvironmentValues {
    /// The root's split, read by the views that place the player, the chapters and the bars.
    var paneLayout: PaneLayout {
        get { self[PaneLayoutKey.self] }
        set { self[PaneLayoutKey.self] = newValue }
    }
}

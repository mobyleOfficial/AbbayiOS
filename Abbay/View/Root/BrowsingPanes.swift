//
//  BrowsingPanes.swift
//  Abbay
//

import SwiftUI

/// A tab's content when the window is split (#255): browsing, with the player pane on its trailing
/// side once a book is presented (A). While the chapters are open (B), the player moves to the
/// leading side and the chapters take the trailing one, in browsing's room (#271, as the spec's
/// mockup). In one pane it is the tab's content alone, and the expansion overlay presents the player.
///
/// Applied inside each tab, around its `NavigationStack`, so the system's tab bar (top on an iPad,
/// a side strip on the iPhone Duo) keeps its own place in the window. Only the selected tab hosts
/// the pane: the hand-built tabs keep the hidden one alive, and its pane would tick for nothing.
///
/// Browsing stays alive under the chapters (hidden, not removed), so closing them returns to the
/// same scroll position, query and pushed page.
struct BrowsingPanes: ViewModifier {
    let isSelected: Bool
    let models: PlayerDetailsModels

    @Environment(\.paneLayout)
    private var layout
    @Environment(PlayerPresentation.self)
    private var presentation
    @ReduceMotion
    private var reduceMotion
    /// The player pane slides between its A and B sides instead of fading out and in.
    @Namespace
    private var panes

    func body(content: Content) -> some View {
        // Read only when split: in one pane, a drag up on the bar presents a book, and nothing
        // here should re-render under it.
        let book = layout.isSplit && isSelected ? presentation.presentedBook : nil
        let showsChapters = book != nil && presentation.isShowingChapters
        // Browsing keeps its slot (the middle one) in every state, so it is never rebuilt: under the
        // chapters it is only hidden.
        HStack(spacing: 0) {
            if showsChapters, let book, let width = layout.playerWidth {
                playerPane(book, width: width)
            }
            content
                .environment(\.isBrowsingCovered, showsChapters)
                .opacity(showsChapters ? 0 : 1)
                .allowsHitTesting(!showsChapters)
                .accessibilityHidden(showsChapters)
                .overlay {
                    if showsChapters, let book {
                        ChaptersPane(book: book, models: models)
                            .transition(.opacity)
                    }
                }
            if !showsChapters, let book, let width = layout.playerWidth {
                playerPane(book, width: width)
            }
        }
        .animation(animation, value: book?.url)
        .animation(animation, value: showsChapters)
    }

    private func playerPane(_ book: AudioModel, width: CGFloat) -> some View {
        PlayerPane(book: book, models: models)
            .frame(width: width)
            .matchedGeometryEffect(id: "player", in: panes, isSource: true)
            .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : PlayerPresentation.animation
    }
}

// MARK: - Covered browsing

private struct BrowsingCoveredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The chapters stand in browsing's place (B). Browsing is only hidden, so its navigation bar
    /// would still show where the system puts it (the unfolded iPhone Duo's side strip, when
    /// browsing is at the window's trailing edge): `HiddenNavigationBarWhileCovered` removes it.
    var isBrowsingCovered: Bool {
        get { self[BrowsingCoveredKey.self] }
        set { self[BrowsingCoveredKey.self] = newValue }
    }
}

/// Hides a browsing page's navigation bar (and its toolbar items) while the chapters cover it.
/// Applied inside each tab's `NavigationStack`, on every page, like `TabBarHiddenWhilePlayerIsOpen`.
struct HiddenNavigationBarWhileCovered: ViewModifier {
    @Environment(\.isBrowsingCovered)
    private var isCovered

    func body(content: Content) -> some View {
        content.toolbar(isCovered ? .hidden : .automatic, for: .navigationBar)
    }
}

// MARK: - Player pane

/// The player as a pane beside browsing: the same `PlayerView` as the full-screen one, on the cover
/// tint, under a close button. It shares the expansion's model (`PlayerDetailsModels`), so a fold
/// that swaps the full-screen player for this pane keeps the same book and state.
private struct PlayerPane: View {
    let book: AudioModel
    let models: PlayerDetailsModels

    @Environment(PlayerPresentation.self)
    private var presentation
    @Environment(PlaybackState.self)
    private var playback
    @Environment(\.playbackCenter)
    private var center
    @Environment(\.downloadStateStore)
    private var downloads

    /// The glass circle's side; the button's hit area stays at least 44 pt.
    @ScaledMetric(relativeTo: .body)
    private var closeSide: CGFloat = 36

    var body: some View {
        let model = models.model(
            for: book,
            presentationID: presentation.presentationID,
            state: playback,
            player: center?.player,
            downloads: downloads
        )
        VStack(spacing: 0) {
            header
            PlayerView(model: model)
                .id(book.url)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            // The cover tint, behind the status bar and any system strip on this edge too.
            Color.clear
                .modifier(CoverTintBackground(book: model.book, style: .playerGradient))
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { presentation.close(animated: true) }
    }

    /// The close button, at the leading edge like the full-screen player's (it reads ✕ here: the
    /// pane leaves sideways, it doesn't collapse).
    private var header: some View {
        HStack {
            Button {
                presentation.close(animated: true)
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(side: closeSide)
                    .abbayGlass(in: Circle(), interactive: true)
                    .frame(side: max(closeSide, SpaceConstants.sx44.value))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(ColorConstants.white.value)
            .accessibilityLabel(Localizable.closePlayer.localized)
            .accessibilityIdentifier(AccessibilityID.Player.close)
            Spacer()
        }
        .padding(.horizontal, SpaceConstants.sx12.value)
        .frame(height: SpaceConstants.sx44.value)
    }
}

// MARK: - Chapters pane

/// The presented book's chapters in browsing's place (B): the persistent form of the chapter
/// panel. A chapter tap plays it and keeps the pane; its ✕ (or the player's pill) closes it.
private struct ChaptersPane: View {
    let book: AudioModel
    let models: PlayerDetailsModels

    @Environment(PlayerPresentation.self)
    private var presentation
    @Environment(PlaybackState.self)
    private var playback
    @Environment(\.playbackCenter)
    private var center
    @Environment(\.downloadStateStore)
    private var downloads
    @ReduceMotion
    private var reduceMotion

    var body: some View {
        let model = models.model(
            for: book,
            presentationID: presentation.presentationID,
            state: playback,
            player: center?.player,
            downloads: downloads
        )
        ChaptersPanel(
            model: model,
            isPresented: Binding(
                get: { [presentation] in presentation.isShowingChapters },
                set: { [presentation] in presentation.setChapters(open: $0) }
            ),
            closeAnimation: reduceMotion ? .easeInOut(duration: 0.2) : PlayerPresentation.animation,
            style: .pane
        )
        .id(book.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorConstants.background.value.ignoresSafeArea())
    }
}

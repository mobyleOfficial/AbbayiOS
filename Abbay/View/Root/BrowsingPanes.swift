//
//  BrowsingPanes.swift
//  Abbay
//

import SwiftUI

/// A tab's content when the window is split (#255): browsing, with the player pane beside it once a
/// book is presented (A), and the chapters in browsing's place while they are open (B). In one pane
/// it is the tab's content alone, and the expansion overlay presents the player.
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

    func body(content: Content) -> some View {
        // Read only when split: in one pane, a drag up on the bar presents a book, and nothing
        // here should re-render under it.
        let book = layout.isSplit && isSelected ? presentation.presentedBook : nil
        let showsChapters = book != nil && presentation.isShowingChapters
        HStack(spacing: 0) {
            content
                .opacity(showsChapters ? 0 : 1)
                .allowsHitTesting(!showsChapters)
                .accessibilityHidden(showsChapters)
                .overlay {
                    if showsChapters, let book {
                        ChaptersPane(book: book, models: models)
                            .transition(.opacity)
                    }
                }
            if let book, let width = layout.playerWidth {
                PlayerPane(book: book, models: models)
                    .frame(width: width)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(animation, value: book?.url)
        .animation(animation, value: showsChapters)
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : PlayerPresentation.animation
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

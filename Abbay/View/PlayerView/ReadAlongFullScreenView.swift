//
//  ReadAlongFullScreenView.swift
//  Abbay
//

import SwiftUI

/// What the root needs to draw the read-along text over the whole window (#192, owner's follow-up):
/// the player screen's own model, scrubber and session slot, so the full screen shows the very
/// session the square shows. Nothing is prepared again and *Preparing text…* doesn't flash; the
/// clock, the scrubbed time and a line tap's seek are the player's.
///
/// Kept on `PlayerPresentation` (`readAlongFullScreen`), not in the player: on the iPhone Duo and
/// a split iPad the player is a pane beside browsing, and the text covers both panes.
@MainActor
struct ReadAlongFullScreen {
    let model: PlayerViewModel
    let scrub: PlayerScrub
    let slot: ReadAlongSessionSlot
    /// The book it opened on.
    let bookURL: URL?

    init(model: PlayerViewModel, scrub: PlayerScrub, slot: ReadAlongSessionSlot) {
        self.model = model
        self.scrub = scrub
        self.slot = slot
        bookURL = model.book.url
    }

    /// The screen still shows the book it opened on. It follows the loaded book after a switch
    /// (Siri, CarPlay): the text then belongs to the other book, and the full screen ends rather
    /// than show book A's text over book B.
    var showsItsBook: Bool {
        model.book.url == bookURL
    }

    /// Expand and collapse: a short scale and fade; a plain fade with Reduce Motion.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity)
    }

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.28)
    }
}

// MARK: - Host

/// Draws the full-screen text, when there is one, above everything the root shows: the tabs, the
/// mini player, the player (full screen or a pane) and browsing. Reads only `readAlongFullScreen`,
/// so nothing else re-renders when it comes and goes.
struct ReadAlongFullScreenHost: View {
    @Environment(PlayerPresentation.self)
    private var presentation
    @ReduceMotion
    private var reduceMotion

    var body: some View {
        let fullScreen = presentation.readAlongFullScreen
        ZStack {
            if let fullScreen, fullScreen.showsItsBook {
                ReadAlongFullScreenView(fullScreen: fullScreen)
                    .transition(ReadAlongFullScreen.transition(reduceMotion: reduceMotion))
            }
        }
        .animation(ReadAlongFullScreen.animation(reduceMotion: reduceMotion), value: fullScreen != nil)
        // The screen followed another loaded book: this text was the other book's.
        .onChange(of: fullScreen?.showsItsBook == false) { _, isStale in
            if isStale { presentation.endReadAlongFullScreen() }
        }
    }
}

// MARK: - Full screen

/// The read-along text over the whole window, on the player's cover tint: the same lines and
/// highlight as the square (`ReadAlongContent`), larger, in a centred column, and a bar along the
/// bottom with the language label, play/pause and the collapse button. No skips (owner's call).
///
/// The background reaches every edge; the text and the bar keep inside the safe area, so the status
/// bar stays readable. VoiceOver treats it as a modal, and its escape gesture collapses it.
struct ReadAlongFullScreenView: View {
    let fullScreen: ReadAlongFullScreen

    @Environment(PlayerPresentation.self)
    private var presentation
    @Environment(ReadAlongCenter.self)
    private var center

    private var model: PlayerViewModel { fullScreen.model }

    var body: some View {
        let session = fullScreen.slot.session(from: center)
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            // Laid out over the whole window, in the window's own coordinates.
            GeometryReader { _ in
                ReadAlongContent(
                    session: session,
                    model: model,
                    scrub: fullScreen.scrub,
                    style: .fullScreen,
                    hidesControls: false
                ) {
                    playPauseButton
                } trailing: {
                    ReadAlongCornerButton(
                        systemImage: "arrow.down.right.and.arrow.up.left",
                        label: Localizable.readAlongExitFullScreen.localized,
                        identifier: AccessibilityID.Player.readAlongCollapse
                    ) {
                        presentation.endReadAlongFullScreen()
                    }
                }
                .padding(.top, insets.top)
                .padding(.leading, insets.leading)
                .padding(.trailing, insets.trailing)
                .padding(.bottom, insets.bottom)
                .background {
                    Color.clear
                        .modifier(CoverTintBackground(book: model.book, style: .playerGradient))
                }
                // Nothing under it takes a touch.
                .contentShape(Rectangle())
            }
            .ignoresSafeArea()
            // On the window-sized view, so the element's frame is the window's.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier(AccessibilityID.Player.readAlongFullScreen)
            .accessibilityAction(.escape) { presentation.endReadAlongFullScreen() }
        }
        .modifier(ReadAlongSessionDriver(
            session: session,
            model: model,
            scrub: fullScreen.scrub,
            slot: fullScreen.slot,
            place: .fullScreen
        ))
    }

    /// The player's own play/pause, bottom-centre.
    private var playPauseButton: some View {
        PlayButtonView(
            isPlaying: .constant(model.isPlaying),
            onPlay: { model.play() },
            onPause: { model.pause() },
            pauseColor: ColorConstants.white.value
        )
        .frame(side: SpaceConstants.sx44.value)
        .padding(.vertical, SpaceConstants.sx4.value)
        .accessibilityIdentifier(AccessibilityID.Player.readAlongPlayPause)
    }
}

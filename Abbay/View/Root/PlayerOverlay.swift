//
//  PlayerOverlay.swift
//  Abbay
//

import SwiftUI

/// Interim presentation of the details screen: a full-screen layer above the tabs that slides up
/// from the bottom as `PlayerPresentation.progress` goes 0 → 1, and back down to close. The
/// close button or a downward drag on the header closes it. Not finger-tracked growth from the
/// bar: the interactive expansion replaces this view.
///
/// The only view that reads `progress`, so animating it re-renders this layer alone.
struct PlayerOverlay: View {
    @Environment(PlayerPresentation.self)
    private var presentation
    /// The header drag, added to the progress offset while the finger is down.
    @State
    private var dragOffset: CGFloat = 0

    private static let closeDistance: CGFloat = 120
    private static let closePredictedDistance: CGFloat = 300

    var body: some View {
        GeometryReader { proxy in
            let travel = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            // A container that is always there, so the offset animates when the content appears.
            ZStack {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: (1 - presentation.progress) * travel + dragOffset)
        }
        .allowsHitTesting(presentation.presentedBook != nil)
        .onChange(of: presentation.presentedBook == nil) { _, isClosed in
            if isClosed { dragOffset = 0 }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let book = presentation.presentedBook {
            VStack(spacing: 0) {
                header
                PlayerView(book)
                    .id(book.url)
            }
            .backgroundColor(ColorConstants.onyx.value)
            .transition(.identity)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { close() }
        }
    }

    /// The drag lives on the header's background, under the close button, so the button keeps its
    /// own 44 pt frame; `simultaneousGesture` lets a drag that starts on the button still close.
    private var header: some View {
        HStack {
            Button {
                close()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(side: SpaceConstants.sx44.value)
                    .contentShape(Rectangle())
            }
            .foregroundColor(ColorConstants.white.value)
            .accessibilityLabel(Localizable.closePlayer.localized)
            .accessibilityIdentifier(AccessibilityID.Player.close)
            .simultaneousGesture(dismissDrag)
            Spacer()
        }
        .padding(.horizontal, SpaceConstants.sx16.value)
        .background {
            // Only the header drags: the chapter list below scrolls.
            Color.clear
                .contentShape(Rectangle())
                .gesture(dismissDrag)
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: SpaceConstants.sx8.value)
            .onChanged { value in
                let offset = max(0, value.translation.height)
                if offset != dragOffset { dragOffset = offset }
            }
            .onEnded { value in
                if value.translation.height > Self.closeDistance
                    || value.predictedEndTranslation.height > Self.closePredictedDistance {
                    close()
                } else {
                    withAnimation(PlayerPresentation.animation) { dragOffset = 0 }
                }
            }
    }

    private func close() {
        presentation.close(animated: true)
    }
}

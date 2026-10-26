//
//  PlayButtonView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 26/06/23.
//

import SwiftUI

struct PlayButtonView: View {
    // MARK: - Properties
    @Binding
    var isPlaying: Bool
    var onPlay: VoidCallback?
    var onPause: VoidCallback?
    var playColor: Color = ColorConstants.white.value
    var pauseColor: Color = ColorConstants.malachite.value

    // MARK: - Body
    var body: some View {
        IconButtonView(systemName: isPlaying ? "pause.fill" : "play.fill") {
            if isPlaying {
                onPause?()
                isPlaying = false
            } else {
                onPlay?()
                isPlaying = true
            }
        }
        .foregroundColor(
            !isPlaying ? playColor : pauseColor
        )
        // The glyph alone gave VoiceOver (and UI tests) no label: say what a tap does.
        .accessibilityLabel(Self.label(isPlaying: isPlaying))
    }

    static func label(isPlaying: Bool) -> String {
        isPlaying ? Localizable.pause.localized : Localizable.play.localized
    }
}

// MARK: - Preview
struct PlayButtonView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewView()
    }

    private struct PreviewView: View {
        @State
        var isPlaying = false

        var body: some View {
            PlayButtonView(
                isPlaying: $isPlaying,
                playColor: ColorConstants.background.value
            )
        }
    }
}

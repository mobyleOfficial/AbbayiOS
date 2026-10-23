//
//  DownloadRingView.swift
//  Abbay
//

import SwiftUI

/// A small progress ring for a book that is still downloading. Tapping it pauses or resumes; a
/// paused ring shows a play glyph.
struct DownloadRingView: View {
    let state: BookDownloadState
    let onTap: VoidCallback

    private var percent: Int {
        Int((min(max(state.fraction, 0), 1) * 100).rounded(.down))
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .stroke(ColorConstants.onyx.value, lineWidth: SpaceConstants.sx2.value)
                Circle()
                    .trim(from: 0, to: min(max(state.fraction, 0), 1))
                    .stroke(ColorConstants.malachite.value, lineWidth: SpaceConstants.sx2.value)
                    .rotationEffect(.degrees(-90))
                if state.isPaused {
                    Image(systemName: "play.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(ColorConstants.malachite.value)
                        .padding(SpaceConstants.sx4.value)
                }
            }
            .frame(side: DownloadRingView.side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            state.isPaused
                ? Localizable.downloadPaused.localized
                : Localizable.downloadingProgress.localized(with: percent)
        )
    }

    static let side: CGFloat = 22
}

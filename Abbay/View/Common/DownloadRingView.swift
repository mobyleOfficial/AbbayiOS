//
//  DownloadRingView.swift
//  Abbay
//

import SwiftUI

/// A small progress ring for a book that is still downloading. Tapping it pauses or resumes; a
/// paused ring shows a play glyph. A download the network holds (`hold`, #171) shows the hold's
/// glyph and says why in its label.
struct DownloadRingView: View {
    let state: BookDownloadState
    var hold: NetworkHold?
    let onTap: VoidCallback

    private var percent: Int {
        Self.percent(state)
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
                if let glyph = Self.glyph(state: state, hold: hold) {
                    Image(systemName: glyph)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(
                            state.isPaused ? ColorConstants.malachite.value : ColorConstants.lightSilver.value
                        )
                        .padding(SpaceConstants.sx4.value)
                }
            }
            .frame(side: DownloadRingView.side)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.label(state: state, hold: hold))
    }

    static let side: CGFloat = 22

    static func percent(_ state: BookDownloadState) -> Int {
        Int((min(max(state.fraction, 0), 1) * 100).rounded(.down))
    }

    /// Paused says so; a held download adds why to its percentage.
    static func label(state: BookDownloadState, hold: NetworkHold?) -> String {
        if state.isPaused { return Localizable.downloadPaused.localized }
        if let hold { return Localizable.downloadingHeld.localized(with: percent(state), hold.message) }
        return Localizable.downloadingProgress.localized(with: percent(state))
    }

    /// Play when paused (tap resumes), the hold's glyph when held, none while it downloads.
    static func glyph(state: BookDownloadState, hold: NetworkHold?) -> String? {
        if state.isPaused { return "play.fill" }
        return hold?.systemImage
    }
}

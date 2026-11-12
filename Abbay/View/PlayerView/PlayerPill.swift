//
//  PlayerPill.swift
//  Abbay
//

import SwiftUI

/// A glass capsule with a label, the look of the speed and chapters pills. The volume pill has
/// only its icon, at a fixed width, so the pill keeps its size as the symbol changes. With
/// `collapsesToIcon`, a pill offered less than its full width shows only its icon, at that same
/// width, instead of truncating its word; its button keeps its accessibility label.
struct PlayerPill: View {
    let text: String?
    var systemImage: String?
    /// For a symbol that draws a level: the volume's waves.
    var variableValue: Double?
    var collapsesToIcon = false

    @ScaledMetric(relativeTo: .subheadline)
    private var iconOnlyWidth: CGFloat = 22

    var body: some View {
        Group {
            if collapsesToIcon, systemImage != nil, text != nil {
                ViewThatFits(in: .horizontal) {
                    content(showsText: true)
                    content(showsText: false)
                }
            } else {
                content(showsText: true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        // 12, not 16: with Read-along on, four pills share a 393 pt iPhone's row with their words.
        .padding(.horizontal, SpaceConstants.sx12.value)
        .padding(.vertical, SpaceConstants.sx8.value + SpaceConstants.sx2.value)
        .abbayGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
    }

    private func content(showsText: Bool) -> some View {
        let shownText = showsText ? text : nil
        return HStack(spacing: SpaceConstants.sx4.value) {
            if let systemImage {
                Image(systemName: systemImage, variableValue: variableValue)
                    .frame(width: shownText == nil ? iconOnlyWidth : nil)
                    .accessibilityHidden(true)
            }
            if let shownText {
                Text(shownText)
            }
        }
    }
}

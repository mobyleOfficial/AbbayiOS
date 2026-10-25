//
//  ProgressView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import SwiftUI

/// The player's scrubber (G1): a 6 pt capsule track with a white fill, and under it the elapsed
/// time, an optional centre label (the current chapter's name, truncating) and the time remaining
/// ("−28:07"). A touch anywhere along the track scrubs, as before; the thumb shows while it does.
struct PlayerProgressView: View {
    // MARK: - Properties
    @Binding
    var currentTime: Double
    var totalTime: Double
    /// Text between the two times, e.g. the current chapter's title.
    var centerLabel: String?
    var onStartUpdate: VoidCallback?
    var onUpdate: ((Double) -> Void)?
    var onFinishUpdate: ((Double) -> Void)?

    // MARK: - States
    @State
    private var isDragging = false

    static let trackHeight: CGFloat = 6
    private static let thumbSide = SpaceConstants.sx16.value

    /// The filled share of the track, 0...1, for any (even zero or non-finite) total.
    static func fraction(current: Double, total: Double) -> Double {
        guard total.isFinite, total > 0, current.isFinite else { return 0 }
        return min(max(current / total, 0), 1)
    }

    /// The trailing label: the time still to play, with a minus sign ("−28:07").
    static func remainingText(current: Double, total: Double) -> String {
        let remaining = max((total.isFinite ? total : 0) - (current.isFinite ? current : 0), 0)
        return "\u{2212}" + clockText(remaining)
    }

    /// "17:12" under an hour, "1:05:09" from an hour on: the scrubber's compact times.
    static func clockText(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(Int(seconds), 0) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: SpaceConstants.sx8.value) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let fraction = Self.fraction(current: currentTime, total: totalTime)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ColorConstants.white.value.opacity(0.2))
                    Capsule()
                        .fill(ColorConstants.white.value)
                        .frame(width: width * fraction)
                    Circle()
                        .fill(ColorConstants.white.value)
                        .frame(side: Self.thumbSide)
                        .opacity(isDragging ? 1 : 0)
                        .offset(x: width * fraction - Self.thumbSide / 2)
                }
                .frame(height: Self.trackHeight)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTouch(limitToBounds: false) { _ in
                    onStartUpdate?()
                } onTouchesMoved: { location in
                    let pos = location.x
                    guard 0...width ~= pos, totalTime > 0 else { return }
                    currentTime = (pos * totalTime) / width
                    isDragging = true
                    onUpdate?(currentTime)
                } onTouchesEnded: { _ in
                    isDragging = false
                    onFinishUpdate?(currentTime)
                }
            }
            // A taller touch area than the 6 pt track.
            .frame(height: SpaceConstants.sx24.value)
            HStack(spacing: SpaceConstants.sx8.value) {
                Text(Self.clockText(currentTime))
                Spacer(minLength: 0)
                if let centerLabel {
                    Text(centerLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                }
                Text(Self.remainingText(current: currentTime, total: totalTime))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(ColorConstants.white.value.opacity(0.6))
        }
    }
}

// MARK: - Preview
struct ProgressView_Previews: PreviewProvider {
    private struct ProgressPreview: View {
        @State
        var currentTime: Double = 1500

        var body: some View {
            PlayerProgressView(
                currentTime: $currentTime,
                totalTime: 3000,
                centerLabel: "A Case of Identity"
            )
            .padding(SpaceConstants.sx16.value)
        }
    }

    static var previews: some View {
        ProgressPreview()
            .preferredColorScheme(.dark)
    }
}

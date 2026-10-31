//
//  VolumeSlider.swift
//  Abbay
//

import SwiftUI

/// Abbay's own volume (`BookVolume`) as a vertical glass capsule over the player: the level on top,
/// a fill to drag up and down, the speaker at the bottom. It rises from the volume pill and a tap
/// outside closes it. The level is the player's gain, never the system volume, so on the Mac a
/// call stays loud while the book is dimmed under it.
struct VolumeSlider: View {
    let volume: Double
    let onChange: (Double) -> Void
    let onClose: () -> Void

    /// The track's width inside the capsule.
    private static let trackWidth = SpaceConstants.sx24.value + SpaceConstants.sx4.value

    var body: some View {
        VStack(spacing: SpaceConstants.sx8.value) {
            Text(BookVolume.label(volume))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            track
            Image(systemName: BookVolume.symbol(volume), variableValue: volume)
                .font(.subheadline)
        }
        .padding(.vertical, SpaceConstants.sx12.value)
        .padding(.horizontal, SpaceConstants.sx4.value)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(ColorConstants.white.value)
        .abbayGlass(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Localizable.bookVolume.localized)
        .accessibilityValue(BookVolume.label(volume))
        .accessibilityAdjustableAction { direction in
            if let level = BookVolume.adjusted(volume, direction) {
                onChange(level)
            }
        }
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier(AccessibilityID.Player.volumeSlider)
    }

    /// The fill grows from the bottom; a touch or a drag anywhere on it sets the level there.
    private var track: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.25)
                ColorConstants.white.value
                    .frame(height: height * volume)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let level = BookVolume.snap(1 - drag.location.y / height)
                        if level != volume {
                            onChange(level)
                        }
                    }
            )
        }
        .frame(width: Self.trackWidth)
    }
}

extension BookVolume {
    /// One VoiceOver swipe up or down: 10%, so the whole range is ten swipes. Nil at either end,
    /// or for a direction that isn't up or down.
    static func adjusted(_ volume: Double, _ direction: AccessibilityAdjustmentDirection) -> Double? {
        let level: Double
        switch direction {
        case .increment: level = stepped(volume, by: 2)
        case .decrement: level = stepped(volume, by: -2)
        @unknown default: return nil
        }
        return level == snap(volume) ? nil : level
    }
}

/// Where the volume capsule sits, in the details screen's own coordinates: centred over the
/// volume pill, its bottom just above the pill, kept inside the screen. Pure, so it is unit tested.
enum VolumeSliderLayout {
    static let width: CGFloat = SpaceConstants.sx48.value + SpaceConstants.sx4.value
    /// The most it asks for; a short screen (a phone in landscape) gets a shorter capsule.
    static let height: CGFloat = SpaceConstants.sx72.value * 3
    /// Between the capsule and the pill, and the capsule and the screen's edges.
    static let gap: CGFloat = SpaceConstants.sx8.value

    static func frame(container: CGSize, pill: CGRect) -> CGRect {
        let bottom = max(pill.minY - gap, 0)
        let capsuleHeight = min(height, max(bottom - gap, 0))
        let maxX = max(container.width - width - gap, gap)
        let x = min(max(pill.midX - width / 2, gap), maxX)
        return CGRect(x: x, y: bottom - capsuleHeight, width: width, height: capsuleHeight)
    }
}

/// The volume pill beside the speed: the speaker, its waves filled to the level; green while the
/// book is dimmed, as the speed pill is away from 1.0×. A tap raises the capsule, a second closes
/// it. VoiceOver adjusts the level right here, without opening it.
struct VolumePill: View {
    let model: PlayerViewModel
    @Binding var isShowing: Bool
    let animation: Animation

    @Environment(AppSettings.self)
    private var settings

    var body: some View {
        let volume = model.volume(in: settings)
        Button {
            withAnimation(animation) { isShowing.toggle() }
        } label: {
            PlayerPill(text: nil, systemImage: BookVolume.symbol(volume), variableValue: volume)
        }
        .buttonStyle(.plain)
        .foregroundColor(volume == BookVolume.full ? ColorConstants.white.value : ColorConstants.malachite.value)
        .accessibilityLabel(Localizable.bookVolume.localized)
        .accessibilityValue(BookVolume.label(volume))
        .accessibilityAdjustableAction { direction in
            if let level = BookVolume.adjusted(volume, direction) {
                model.setVolume(level, in: settings)
            }
        }
        .accessibilityIdentifier(AccessibilityID.Player.volume)
        .anchorPreference(key: VolumePillAnchorKey.self, value: .bounds) { $0 }
    }
}

/// The capsule over the player screen, placed from the pill's bounds (`VolumeSliderLayout`). No
/// dim: the screen stays as it was, and a tap anywhere else (the pill's own included) closes it.
struct VolumeCapsuleOverlay: ViewModifier {
    let model: PlayerViewModel
    @Binding var isShowing: Bool
    let animation: Animation

    @Environment(AppSettings.self)
    private var settings
    @ReduceMotion
    private var reduceMotion

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(VolumePillAnchorKey.self) { pill in
            if isShowing, let pill {
                GeometryReader { proxy in
                    let frame = VolumeSliderLayout.frame(container: proxy.size, pill: proxy[pill])
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .padding(.top, -PlayerView.dimReach)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                            .accessibilityHidden(true)
                        VolumeSlider(
                            volume: model.volume(in: settings),
                            onChange: { model.setVolume($0, in: settings) },
                            onClose: close
                        )
                        .frame(width: frame.width, height: frame.height)
                        .padding(.leading, frame.minX)
                        .padding(.top, frame.minY)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(transition)
                    }
                }
            }
        }
    }

    /// Grows up out of the pill and fades; with Reduce Motion it only fades.
    private var transition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity)
    }

    private func close() {
        withAnimation(animation) { isShowing = false }
    }
}

/// Where the volume pill is, for the capsule above it. The last one reported wins, like the pills'.
private struct VolumePillAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

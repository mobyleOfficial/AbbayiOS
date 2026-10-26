//
//  SpeedControlView.swift
//  Abbay
//

import SwiftUI

/// The speed control of the Android app's speed sheet: − / the speed / +, a 0.5–3.5× slider in
/// 0.05 steps, and preset chips. Used by the player's speed sheet and Settings' default speed page.
struct SpeedControlView: View {
    let speed: Double
    let onChange: (Double) -> Void

    /// Seven chips of this width fit one row on a 375 pt wide screen at the default text size.
    @ScaledMetric(relativeTo: .subheadline)
    private var chipWidth: CGFloat = 43
    @ScaledMetric(relativeTo: .subheadline)
    private var chipHeight: CGFloat = SpaceConstants.sx36.value

    var body: some View {
        VStack(spacing: SpaceConstants.sx16.value) {
            stepper
            Slider(
                value: Binding(get: { speed }, set: { onChange(PlaybackSpeed.snap($0)) }),
                in: PlaybackSpeed.minimum...PlaybackSpeed.maximum,
                step: PlaybackSpeed.step
            )
            .tint(ColorConstants.malachite.value)
            .accessibilityLabel(Localizable.playbackSpeed.localized)
            .accessibilityValue(PlaybackSpeed.label(speed))
            .accessibilityIdentifier(AccessibilityID.Speed.slider)
            presets
        }
    }

    private var stepper: some View {
        HStack(spacing: SpaceConstants.sx16.value) {
            stepButton(systemName: "minus", label: .speedDecrease, identifier: AccessibilityID.Speed.decrease, by: -1)
                .disabled(speed <= PlaybackSpeed.minimum)
            Text(PlaybackSpeed.label(speed))
                .font(.largeTitle.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Localizable.playbackSpeed.localized)
                .accessibilityValue(PlaybackSpeed.label(speed))
                .accessibilityIdentifier(AccessibilityID.Speed.value)
            stepButton(systemName: "plus", label: .speedIncrease, identifier: AccessibilityID.Speed.increase, by: 1)
                .disabled(speed >= PlaybackSpeed.maximum)
        }
    }

    private func stepButton(systemName: String, label: Localizable, identifier: String, by count: Int) -> some View {
        Button {
            onChange(PlaybackSpeed.stepped(speed, by: count))
        } label: {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .frame(minWidth: SpaceConstants.sx44.value, minHeight: SpaceConstants.sx44.value)
                .background(ColorConstants.onyx.value, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundColor(ColorConstants.white.value)
        .accessibilityLabel(label.localized)
        .accessibilityIdentifier(identifier)
    }

    /// The preset chips in one row, all the same width (#166 G7): glass capsules, the selected one
    /// solid malachite. When the row doesn't fit (large text), the same row scrolls sideways.
    private var presets: some View {
        ViewThatFits(in: .horizontal) {
            presetRow
            ScrollView(.horizontal, showsIndicators: false) {
                presetRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localizable.speedPresets.localized)
    }

    private var presetRow: some View {
        AbbayGlassContainer(spacing: SpaceConstants.sx4.value) {
            HStack(spacing: SpaceConstants.sx4.value) {
                ForEach(PlaybackSpeed.presets, id: \.self) { preset in
                    presetChip(preset)
                }
            }
        }
    }

    @ViewBuilder
    private func presetChip(_ preset: Double) -> some View {
        let isSelected = preset == speed
        let label = Text(PlaybackSpeed.label(preset))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: chipWidth, height: chipHeight)
        Button {
            onChange(preset)
        } label: {
            if isSelected {
                label
                    .foregroundColor(ColorConstants.background2.value)
                    .background(ColorConstants.malachite.value, in: Capsule())
            } else {
                label
                    .foregroundColor(ColorConstants.white.value)
                    .abbayGlass(in: Capsule(), interactive: true)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Speed.preset(preset))
    }
}

/// The player's speed sheet: the control for the shown book, and "Set as default for new books".
struct SpeedSheetView: View {
    let speed: Double
    let defaultSpeed: Double
    let onChange: (Double) -> Void
    let onSetDefault: (Double) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceConstants.sx16.value) {
                Text(Localizable.playbackSpeed.localized)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                SpeedControlView(speed: speed, onChange: onChange)
                setDefaultButton
            }
            .padding(SpaceConstants.sx24.value)
        }
        .foregroundColor(ColorConstants.white.value)
        .background(ColorConstants.background.value.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var setDefaultButton: some View {
        let isDefault = speed == defaultSpeed
        Button {
            onSetDefault(speed)
        } label: {
            Label(
                isDefault ? Localizable.speedIsDefault.localized : Localizable.speedSetDefault.localized,
                systemImage: isDefault ? "checkmark.circle.fill" : "star"
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpaceConstants.sx12.value)
        }
        .buttonStyle(.plain)
        .foregroundColor(isDefault ? ColorConstants.lightSilver.value : ColorConstants.malachite.value)
        .disabled(isDefault)
        .accessibilityIdentifier(AccessibilityID.Speed.setDefault)
    }
}

struct SpeedSheetView_Previews: PreviewProvider {
    static var previews: some View {
        SpeedSheetView(speed: 1.25, defaultSpeed: 1, onChange: { _ in }, onSetDefault: { _ in })
    }
}

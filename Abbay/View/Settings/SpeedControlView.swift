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

    @ScaledMetric(relativeTo: .body)
    private var chipWidth: CGFloat = SpaceConstants.sx72.value

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

    private var presets: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: chipWidth), spacing: SpaceConstants.sx8.value)]) {
            ForEach(PlaybackSpeed.presets, id: \.self) { preset in
                let isSelected = preset == speed
                Button {
                    onChange(preset)
                } label: {
                    Text(PlaybackSpeed.label(preset))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SpaceConstants.sx8.value)
                        .foregroundColor(isSelected ? ColorConstants.background2.value : ColorConstants.white.value)
                        .background(
                            isSelected ? ColorConstants.malachite.value : ColorConstants.onyx.value,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(AccessibilityID.Speed.preset(preset))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Localizable.speedPresets.localized)
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

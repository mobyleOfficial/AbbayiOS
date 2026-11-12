//
//  SleepReturnPromptView.swift
//  Abbay
//

import SwiftUI

/// "🌙 Back to where you fell asleep · 1:00  ✕": a glass capsule over the bottom of the cover, after
/// the sleep timer paused the book (#332). Modelled on the *Resumed at · Start over* prompt (#299),
/// but it doesn't time out: it stays until it is used or dismissed, or `SleepReturnCenter` drops
/// the spot. VoiceOver announces it when it appears.
struct SleepReturnPromptView: View {
    let spot: SleepReturnSpot
    let onGoBack: () -> Void
    let onDismiss: () -> Void

    private var time: String {
        PlayerProgressView.clockText(spot.returnTo)
    }

    var body: some View {
        HStack(spacing: SpaceConstants.sx12.value) {
            Button(action: onGoBack) {
                HStack(spacing: SpaceConstants.sx8.value) {
                    Image(systemName: "moon.fill")
                        .foregroundColor(ColorConstants.malachite.value)
                        .accessibilityHidden(true)
                    Text(Localizable.sleepReturnBack.localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorConstants.white.value)
                        .multilineTextAlignment(.leading)
                    Text(time)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(ColorConstants.white.value.opacity(0.8))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Localizable.sleepReturnBack.localized), \(time)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(AccessibilityID.Player.sleepReturnGo)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(ColorConstants.white.value.opacity(0.7))
                    .frame(width: SpaceConstants.sx24.value, height: SpaceConstants.sx24.value)
                    .contentShape(Rectangle().inset(by: -SpaceConstants.sx8.value))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localizable.sleepReturnDismiss.localized)
            .accessibilityIdentifier(AccessibilityID.Player.sleepReturnDismiss)
        }
        .padding(.leading, SpaceConstants.sx20.value)
        .padding(.trailing, SpaceConstants.sx12.value)
        .padding(.vertical, SpaceConstants.sx12.value)
        .abbayGlass(in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: SpaceConstants.sx12.value, y: SpaceConstants.sx4.value)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Player.sleepReturn)
        .onAppear {
            AccessibilityNotification.Announcement("\(Localizable.sleepReturnBack.localized), \(time)").post()
        }
    }
}

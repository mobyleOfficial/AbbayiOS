//
//  ResumePromptView.swift
//  Abbay
//

import SwiftUI

/// A chapter tap that resumed partway into the chapter (#299): which book and chapter, and the
/// book time it resumed at. Shown briefly on the player, offering to start the chapter over.
struct ResumePrompt: Equatable, Identifiable {
    let id = UUID()
    let bookURL: URL?
    let chapterIndex: Int
    let time: Double

    /// How long the prompt stays up.
    static let duration: Duration = .seconds(6)
    /// A resume this close to the chapter's start is a start: no prompt.
    static let minimumOffset: Double = 1
}

/// "Resumed at 3:20 · ↺ Start over": a glass capsule over the bottom of the cover, above the title.
/// It appears after a chapter tap resumed partway in and goes after `ResumePrompt.duration`.
/// VoiceOver announces it, and can reach its button while it shows.
struct ResumePromptView: View {
    let prompt: ResumePrompt
    let onStartOver: () -> Void

    private var message: String {
        Localizable.resumedAt.localized(with: PlayerProgressView.clockText(prompt.time))
    }

    var body: some View {
        HStack(spacing: SpaceConstants.sx12.value) {
            Text(message)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(ColorConstants.white.value.opacity(0.8))
                .lineLimit(1)
                .accessibilityIdentifier(AccessibilityID.Player.resumePrompt)
            Button(action: onStartOver) {
                Label(Localizable.startOver.localized, systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorConstants.white.value)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Player.resumePromptStartOver)
        }
        .padding(.horizontal, SpaceConstants.sx20.value)
        .padding(.vertical, SpaceConstants.sx12.value)
        .abbayGlass(in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: SpaceConstants.sx12.value, y: SpaceConstants.sx4.value)
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

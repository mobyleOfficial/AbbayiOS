//
//  SleepTimerPill.swift
//  Abbay
//

import SwiftUI

/// The moon beside the speed and volume (#332), where Apple Books keeps its sleep timer. Off, an
/// outlined moon; set to the end of the chapter, a filled one; counting down, a filled moon and the
/// time left (`12:34`). A tap opens the choices; the one running is checked, and *Off* cancels it.
///
/// The choices are a popover, not a `Menu`: on iOS 27 a menu growing out of the pill lies over the
/// Text and Chapters pills, and their interactive glass took the taps meant for the menu's bottom
/// rows. A popover is presented over everything, so nothing underneath can take its touches.
///
/// When the pill row runs short, Text and then Chapters drop their words first (they have lower
/// layout priority); only then does the countdown give way to the moon alone. VoiceOver still reads
/// the time left.
struct SleepTimerPill: View {
    let timer: SleepTimer
    /// Whether the book has chapters: only then is *When current chapter ends* offered.
    let hasChapters: Bool

    @State
    private var isShowingChoices = false

    var body: some View {
        Group {
            if case .duration = timer.choice {
                // Ticks only while a duration runs, so an idle pill costs nothing.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    pill(remaining: timer.remaining())
                }
            } else {
                pill(remaining: nil)
            }
        }
        .popover(isPresented: $isShowingChoices) {
            SleepTimerChoicesView(timer: timer, hasChapters: hasChapters) {
                isShowingChoices = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func pill(remaining: TimeInterval?) -> some View {
        let choice = timer.choice
        return Button {
            isShowingChoices = true
        } label: {
            PlayerPill(
                text: remaining.map(Self.countdown),
                systemImage: choice == nil ? "moon" : "moon.fill",
                collapsesToIcon: true
            )
            .monospacedDigit()
        }
        .buttonStyle(.plain)
        .foregroundColor(choice == nil ? ColorConstants.white.value : ColorConstants.malachite.value)
        .accessibilityLabel(Localizable.sleepTimer.localized)
        .accessibilityValue(Self.accessibilityValue(choice: choice, remaining: remaining))
        .accessibilityIdentifier(AccessibilityID.Player.sleepTimer)
    }
}

/// The popover's list: a *Sleep timer* header, *Off*, *When current chapter ends* (with chapters),
/// and the durations. A choice sets the timer and closes the popover.
private struct SleepTimerChoicesView: View {
    let timer: SleepTimer
    let hasChapters: Bool
    let onChoose: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            list
            ScrollView { list }
        }
        .frame(minWidth: 240)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Localizable.sleepTimer.localized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, SpaceConstants.sx16.value)
                .padding(.top, SpaceConstants.sx12.value)
                .padding(.bottom, SpaceConstants.sx4.value)
                .accessibilityAddTraits(.isHeader)
            row(nil)
            ForEach(timer.choices(forChapters: hasChapters), id: \.self) { option in
                row(option)
            }
        }
        .padding(.bottom, SpaceConstants.sx8.value)
    }

    private func row(_ option: SleepTimerChoice?) -> some View {
        let isSelected = option == timer.choice
        return Button {
            timer.set(option)
            onChoose()
        } label: {
            HStack(spacing: SpaceConstants.sx12.value) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
                Text(option.map(SleepTimerPill.title) ?? Localizable.sleepTimerOff.localized)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SpaceConstants.sx16.value)
            .frame(minHeight: SpaceConstants.sx44.value)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension SleepTimerPill {
    /// A menu choice: *When current chapter ends*, *5 minutes* … *45 minutes*, *1 hour*.
    static func title(of choice: SleepTimerChoice) -> String {
        switch choice {
        case .endOfChapter:
            return Localizable.sleepTimerEndOfChapter.localized
        case let .duration(seconds) where seconds >= 3600:
            return Localizable.sleepTimerOneHour.localized
        case let .duration(seconds):
            return Localizable.sleepTimerMinutes.localized(with: Int(seconds / 60))
        }
    }

    /// The time left on the pill, rounded up so it never reads 0:00 while running.
    static func countdown(_ remaining: TimeInterval) -> String {
        PlayerProgressView.clockText(remaining.rounded(.up))
    }

    /// *Off*, *When current chapter ends*, *12 minutes left* (whole minutes, rounded up), or *Less
    /// than a minute left*.
    static func accessibilityValue(choice: SleepTimerChoice?, remaining: TimeInterval?) -> String {
        switch choice {
        case nil:
            return Localizable.sleepTimerOff.localized
        case .endOfChapter:
            return Localizable.sleepTimerEndOfChapter.localized
        case .duration:
            let seconds = remaining ?? 0
            guard seconds >= 60 else { return Localizable.sleepTimerUnderAMinute.localized }
            return Localizable.sleepTimerMinutesLeft.localized(with: Int((seconds / 60).rounded(.up)))
        }
    }
}

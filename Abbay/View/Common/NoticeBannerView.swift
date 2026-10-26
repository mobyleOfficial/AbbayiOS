//
//  NoticeBannerView.swift
//  Abbay
//

import SwiftUI

/// The banner for `NoticeCenter.current`: a glass capsule near the top of the screen, above the
/// tabs and the details screen, that slides in and dismisses itself. Red is only its icon. It sits
/// just under the navigation bar's row, so it covers neither the toolbar at the top nor the mini
/// player and the tab bar at the bottom.
///
/// It doesn't take touches: taps go through to whatever is under it, so a notice never blocks
/// the screen it appears over. VoiceOver hears the message as an announcement
/// (`NoticeCenter.postAnnouncement`) and can still focus the banner, which offers *Dismiss*.
struct NoticeBannerView: View {
    @Environment(NoticeCenter.self)
    private var notices

    var body: some View {
        VStack {
            if let presented = notices.current {
                banner(presented)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: notices.current?.id)
    }

    /// From the top of the safe area: past a navigation bar's 44 pt row and a little air.
    static let topInset: CGFloat = SpaceConstants.sx52.value

    private func banner(_ presented: NoticeCenter.Presented) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SpaceConstants.sx12.value) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(ColorConstants.maximumRed.value)
                .accessibilityHidden(true)
            Text(presented.message)
                .font(.subheadline)
                .foregroundColor(ColorConstants.white.value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, SpaceConstants.sx20.value)
        .padding(.vertical, SpaceConstants.sx12.value)
        // A one-line notice is exactly a capsule; a longer one keeps the same rounded ends.
        .abbayGlass(in: RoundedRectangle(cornerRadius: SpaceConstants.sx24.value, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: SpaceConstants.sx12.value, y: SpaceConstants.sx4.value)
        .padding(.horizontal, SpaceConstants.sx16.value)
        // Below the navigation bar's row, so the toolbar (+ / gear, the player's close) stays
        // visible and reachable while a notice shows.
        .padding(.top, Self.topInset)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction(named: Localizable.noticeDismiss.localized) { notices.dismiss() }
        .accessibilityIdentifier(AccessibilityID.Notice.banner)
    }
}

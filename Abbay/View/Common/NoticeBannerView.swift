//
//  NoticeBannerView.swift
//  Abbay
//

import SwiftUI

/// The banner for `NoticeCenter.current`: a small card at the top of the screen, above the tabs
/// and the details screen, that slides in and dismisses itself. Being at the top, it never covers
/// the mini player or the tab bar at the bottom.
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
        .padding(.horizontal, SpaceConstants.sx16.value)
        .padding(.vertical, SpaceConstants.sx12.value)
        .background(
            ColorConstants.onyx.value,
            in: RoundedRectangle(cornerRadius: SpaceConstants.sx12.value)
        )
        .shadow(color: ColorConstants.background2.value.opacity(0.6), radius: SpaceConstants.sx8.value)
        .padding(.horizontal, SpaceConstants.sx16.value)
        .padding(.top, SpaceConstants.sx4.value)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityAction(named: Localizable.noticeDismiss.localized) { notices.dismiss() }
        .accessibilityIdentifier(AccessibilityID.Notice.banner)
    }
}

//
//  NoticeCenter.swift
//  Abbay
//

import Foundation
import Observation
import UIKit

protocol NoticeReporting: AnyObject {
    /// Shows `notice` to the user. Safe from any thread: delivery moves to the main thread.
    func report(_ notice: Notice)
}

/// The app's one way of telling the user something failed (#115). Producers (the player, the
/// library, Core Data) report a `Notice`; `NoticeBannerView`, at the root, shows the current one as
/// a banner that dismisses itself. VoiceOver hears it as an announcement.
///
/// One notice at a time: a new one replaces the old, and reporting the one already shown only
/// restarts its timer, so a failure that repeats (an item failing twice) isn't announced twice.
/// `current` is read and written on the main thread only.
@Observable
final class NoticeCenter: NoticeReporting {
    static let shared = NoticeCenter()

    /// A notice on screen. The id changes with every new notice, for the banner's transition.
    struct Presented: Identifiable, Equatable {
        let id = UUID()
        let notice: Notice
        let message: String
    }

    private(set) var current: Presented?

    @ObservationIgnored
    private let displayDuration: () -> TimeInterval
    @ObservationIgnored
    private let announce: (String) -> Void
    @ObservationIgnored
    private var dismissWork: DispatchWorkItem?

    init(
        displayDuration: @escaping () -> TimeInterval = NoticeCenter.defaultDisplayDuration,
        announce: @escaping (String) -> Void = NoticeCenter.postAnnouncement
    ) {
        self.displayDuration = displayDuration
        self.announce = announce
    }

    func report(_ notice: Notice) {
        if Thread.isMainThread {
            show(notice)
        } else {
            DispatchQueue.main.async { [weak self] in self?.show(notice) }
        }
    }

    /// Hides the current notice now (the banner's VoiceOver "Dismiss" action).
    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        current = nil
    }

    private func show(_ notice: Notice) {
        if current?.notice != notice {
            let presented = Presented(notice: notice, message: notice.message)
            current = presented
            announce(presented.message)
        }
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.current = nil
            self?.dismissWork = nil
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration(), execute: work)
    }

    // MARK: - Defaults

    /// Long enough to read a two-line message; longer under VoiceOver, so the banner is still
    /// there to focus once the announcement has been spoken.
    static func defaultDisplayDuration() -> TimeInterval {
        UIAccessibility.isVoiceOverRunning ? 10 : 5
    }

    /// High priority, so the announcement isn't dropped when the failure also moves focus (the
    /// details screen closing, say).
    static func postAnnouncement(_ message: String) {
        let announcement = NSAttributedString(
            string: message,
            attributes: [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.high]
        )
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}

//
//  ReadAlongLanguageMenuButton.swift
//  Abbay
//

import SwiftUI
import UIKit

/// The language label's menu, as a clear UIKit button laid over the SwiftUI glass capsule, so the
/// read-along controls know when the menu opens and closes: they must not hide while it is open, or
/// the menu loses the label it hangs off (#192, immersion).
///
/// SwiftUI's `Menu` says neither: its content's `onAppear` fires once, the first time it opens,
/// and `onDisappear` never (checked on iOS 26.5), and a gesture on its label never fires. A
/// `UIButton` that shows its menu as its primary action is the delegate of its own context-menu
/// interaction, and is told both (`willDisplayMenuFor`, `willEndFor`).
///
/// The capsule underneath draws the label; this button is what VoiceOver and the UI tests find.
struct ReadAlongLanguageMenuButton: UIViewRepresentable {
    let choices: [ReadAlongView.LanguageChoice]
    /// The locale id in use: its entry carries the checkmark.
    let current: String
    /// What the label reads ("English"), for VoiceOver's value.
    let name: String
    let onPick: (String) -> Void
    let onOpenChange: (Bool) -> Void

    func makeUIView(context: Context) -> MenuButton {
        let button = MenuButton(type: .custom)
        button.showsMenuAsPrimaryAction = true
        button.backgroundColor = .clear
        button.accessibilityIdentifier = AccessibilityID.Player.readAlongLanguage
        return button
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateUIView(_ button: MenuButton, context: Context) {
        // Here rather than once at creation: the in-app language can change while the button
        // stays (an iPad with Settings open beside the player).
        button.accessibilityLabel = Localizable.readAlongLanguage.localized
        button.accessibilityValue = name
        button.onOpenChange = onOpenChange
        let coordinator = context.coordinator
        coordinator.onPick = onPick
        // Only when the entries or the checkmark change: the menu opening re-renders this view
        // too, and replacing the menu while it shows is wasted work and may flicker.
        guard coordinator.choices != choices || coordinator.current != current else { return }
        coordinator.choices = choices
        coordinator.current = current
        button.menu = UIMenu(children: choices.map { choice in
            UIAction(title: choice.name, state: choice.id == current ? .on : .off) { [weak coordinator] _ in
                coordinator?.onPick(choice.id)
            }
        })
    }

    /// The inputs the shown menu was built from, and the latest pick handler, which its actions
    /// call so a kept menu never runs a stale one.
    final class Coordinator {
        var choices: [ReadAlongView.LanguageChoice]?
        var current: String?
        var onPick: (String) -> Void = { _ in }
    }

    /// Taken out while its menu is open (the text went away under it): the menu is gone too, so
    /// nothing should stay pinned waiting for a close that won't be reported.
    static func dismantleUIView(_ button: MenuButton, coordinator: Coordinator) {
        guard button.isMenuOpen, let onOpenChange = button.onOpenChange else { return }
        // Not during the update that took it out.
        DispatchQueue.main.async { onOpenChange(false) }
    }

    /// Exactly the capsule it is laid over.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MenuButton, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    final class MenuButton: UIButton {
        var onOpenChange: ((Bool) -> Void)?
        private(set) var isMenuOpen = false

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willDisplayMenuFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
            isMenuOpen = true
            onOpenChange?(true)
        }

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
            isMenuOpen = false
            onOpenChange?(false)
        }
    }
}

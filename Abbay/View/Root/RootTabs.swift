//
//  RootTabs.swift
//  Abbay
//

import SwiftUI

/// The hand-built tab bar for iOS 17.0–26.0, standing in for the system `TabView` used on 26.1+.
/// A `background2` bar with Library and Search, malachite when selected, docked
/// under the content so nothing is covered. The mini player (`accessory`) docks right above the
/// bar, and the content ends above both.
///
/// Both tabs stay alive once visited, like a system tab view: the hidden one keeps its scroll
/// position, query and pushed page, and is hidden from hit testing and accessibility.
struct RootTabs<Library: View, Search: View, Accessory: View>: View {
    @Binding
    var selection: RootTab
    private let library: Library
    private let search: Search
    private let accessory: Accessory

    /// The Search tab is built on its first visit, so launch doesn't load Popular on LibriVox.
    @State
    private var hasVisitedSearch = false

    init(
        selection: Binding<RootTab>,
        @ViewBuilder library: () -> Library,
        @ViewBuilder search: () -> Search,
        @ViewBuilder accessory: () -> Accessory
    ) {
        _selection = selection
        self.library = library()
        self.search = search()
        self.accessory = accessory()
    }

    /// The pages sit above the mini player and the bar in a stack, not under them through a
    /// safe-area inset: on iOS 18 a `List` in a tab's `NavigationStack` ignored that inset (with
    /// the keyboard opt-out below), so its last rows scrolled under the mini player. Laid out
    /// this way, the pages simply end where the mini player starts.
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page(.library) { library }
                if hasVisitedSearch || selection == .search {
                    page(.search) { search }
                }
            }
            accessory
            bar
        }
        // Like a system tab bar, stay put under the keyboard instead of riding above it. Each tab's
        // `NavigationStack` hosts its pages in their own controllers, which still avoid the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: selection, initial: true) { _, tab in
            if tab == .search, !hasVisitedSearch { hasVisitedSearch = true }
        }
    }

    private func page(_ tab: RootTab, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = selection == tab
        return content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }

    private var bar: some View {
        HStack(spacing: 0) {
            item(
                .library,
                title: Localizable.libraryTab.localized,
                systemImage: "books.vertical",
                identifier: AccessibilityID.Root.tabLibrary
            )
            item(
                .search,
                title: Localizable.searchTab.localized,
                systemImage: "magnifyingglass",
                identifier: AccessibilityID.Root.tabSearch
            )
        }
        .padding(.top, SpaceConstants.sx8.value)
        .padding(.bottom, SpaceConstants.sx4.value)
        .frame(maxWidth: .infinity)
        .background(ColorConstants.background2.value.ignoresSafeArea(edges: .bottom))
    }

    private func item(_ tab: RootTab, title: String, systemImage: String, identifier: String) -> some View {
        let isSelected = selection == tab
        return Button {
            if selection != tab { selection = tab }
        } label: {
            VStack(spacing: SpaceConstants.sx2.value) {
                Image(systemName: systemImage)
                    .font(.system(size: SpaceConstants.sx20.value))
                    .frame(height: SpaceConstants.sx24.value)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? ColorConstants.malachite.value : ColorConstants.spanishGray.value)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

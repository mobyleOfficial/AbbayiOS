//
//  SettingsView.swift
//  Abbay
//

import SafariServices
import SwiftUI

/// The Settings sheet, opened from the library toolbar's gear: playback (default speed, skip
/// amounts), downloads (cellular, space used, delete finished), language and About.
///
/// Presented by the root, outside the part of the tree that a language change rebuilds, so it
/// stays open and redraws in the new language at once. Its whole screen is this one body (plus
/// helper functions), which reads `settings.language`, so every string here is re-read on a switch.
struct SettingsView: View {
    @StateObject
    private var model: SettingsViewModel
    @Environment(\.dismiss)
    private var dismiss
    @State
    private var webPage: WebPage?

    private static let privacyPolicyURL = URL(string: "https://mobyleapps.com/abbay/privacy-policy/")
    /// The developer's LinkedIn profile, behind About the developer's button.
    static let linkedInURL = URL(string: "https://www.linkedin.com/in/edyuto")
    private static let libriVoxURL = URL(string: "https://librivox.org")

    init(model: @autoclosure @escaping () -> SettingsViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        @Bindable var settings = model.settings
        // Read here so a language switch re-runs this body, which re-reads every string below.
        let language = settings.language
        NavigationStack {
            Form {
                playbackSection(settings: $settings)
                downloadsSection(settings: $settings)
                languageSection(settings: $settings)
                if #available(iOS 26, *) {
                    experimentalSection(settings: $settings)
                }
                aboutSection
            }
            .navigationTitle(Localizable.settingsTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Localizable.done.localized) { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.Settings.done)
                }
            }
            .task { await model.refresh() }
            .alert(Localizable.deleteFinishedTitle.localized, isPresented: $model.isConfirmingDelete) {
                Button(Localizable.delete.localized, role: .destructive) {
                    Task { await model.confirmDeleteFinished() }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.deleteConfirm)
                Button(Localizable.cancel.localized, role: .cancel) {}
                    .accessibilityIdentifier(AccessibilityID.Settings.deleteCancel)
            } message: {
                Text(Localizable.deleteFinishedMessage.localized(
                    with: SettingsViewModel.formatted(bytes: model.finishedBytes)
                ))
            }
            .sheet(item: $webPage) { page in
                SafariView(url: page.url)
                    .ignoresSafeArea()
            }
        }
        .tint(ColorConstants.malachite.value)
        .foregroundColor(ColorConstants.white.value)
        .preferredColorScheme(.dark)
        .environment(\.locale, language.languageCode.map(Locale.init(identifier:)) ?? .current)
    }

    // MARK: - Playback

    private func playbackSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            NavigationLink {
                DefaultSpeedView(settings: model.settings)
            } label: {
                LabeledContent(
                    Localizable.defaultSpeed.localized,
                    value: PlaybackSpeed.label(settings.wrappedValue.defaultSpeed)
                )
            }
            .accessibilityIdentifier(AccessibilityID.Settings.defaultSpeed)
            skipPicker(.skipBack, selection: settings.skipBackward, symbol: \.backwardSymbol)
                .accessibilityIdentifier(AccessibilityID.Settings.skipBack)
            skipPicker(.skipForward, selection: settings.skipForward, symbol: \.forwardSymbol)
                .accessibilityIdentifier(AccessibilityID.Settings.skipForward)
        } header: {
            Text(Localizable.settingsPlayback.localized)
        } footer: {
            Text(Localizable.skipFooter.localized)
        }
    }

    private func skipPicker(
        _ title: Localizable,
        selection: Binding<SkipInterval>,
        symbol: KeyPath<SkipInterval, String>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(SkipInterval.allCases) { interval in
                // Text only: the row's own label already shows the arrow with the chosen number.
                Text(Localizable.skipSeconds.localized(with: interval.rawValue))
                    .tag(interval)
            }
        } label: {
            Label(title.localized, systemImage: selection.wrappedValue[keyPath: symbol])
        }
        .pickerStyle(.menu)
        // A menu picker built from a `ForEach` keeps showing its selected value in the language it
        // was first drawn in, even though this body re-runs on a switch (#179). A new identity per
        // language makes it draw the value again.
        .id(model.settings.language)
    }

    // MARK: - Downloads

    private func downloadsSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            // A whole-row `Menu` rather than a menu `Picker`: a Form stacks a menu picker's value
            // under a label that doesn't fit beside it (#189), and so does `LabeledContent`. Here a
            // long label wraps and the value stays on the trailing side, the row is as tall as its
            // neighbours, and a tap anywhere on it opens the options (the picker inside gives them
            // their checkmark). VoiceOver reads it as label and value.
            Menu {
                Picker(Localizable.cellularDownloads.localized, selection: settings.cellularPreference) {
                    ForEach(CellularDownloadPreference.allCases) { preference in
                        Text(Self.title(of: preference)).tag(preference)
                    }
                }
            } label: {
                HStack {
                    Text(Localizable.cellularDownloads.localized)
                        .foregroundColor(ColorConstants.white.value)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)
                    Spacer(minLength: SpaceConstants.sx8.value)
                    HStack(spacing: SpaceConstants.sx4.value) {
                        Text(Self.title(of: settings.wrappedValue.cellularPreference))
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                    .foregroundColor(ColorConstants.malachite.value)
                    .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Localizable.cellularDownloads.localized)
            .accessibilityValue(Self.title(of: settings.wrappedValue.cellularPreference))
            .accessibilityIdentifier(AccessibilityID.Settings.cellular)
            LabeledContent(
                Localizable.spaceUsed.localized,
                value: model.bytesUsed.map(SettingsViewModel.formatted(bytes:)) ?? Localizable.calculating.localized
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.Settings.spaceUsed)
            Button(role: .destructive) {
                model.askToDeleteFinished()
            } label: {
                Text(Localizable.deleteFinished.localized)
                    .foregroundColor(
                        model.canDeleteFinished ? ColorConstants.maximumRed.value : ColorConstants.spanishGray.value
                    )
            }
            .disabled(!model.canDeleteFinished)
            .accessibilityIdentifier(AccessibilityID.Settings.deleteFinished)
        } header: {
            Text(Localizable.settingsDownloads.localized)
        } footer: {
            Text(downloadsFooter)
        }
    }

    private var downloadsFooter: String {
        let threshold = ByteSize.text(CellularDownloadPolicy.largeDownloadThreshold)
        let finished = model.canDeleteFinished
            ? Localizable.deleteFinishedFooter.localized
            : Localizable.deleteFinishedNone.localized
        return Localizable.cellularFooter.localized(with: threshold) + "\n\n" + finished
    }

    // MARK: - Language

    private func languageSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            Picker(Localizable.settingsLanguage.localized, selection: settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(Self.name(of: language))
                        .tag(language)
                        .accessibilityIdentifier(AccessibilityID.Settings.language(language.rawValue))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(Localizable.settingsLanguage.localized)
        } footer: {
            Text(Localizable.languageFooter.localized)
        }
    }

    /// Each language is named in itself, so it can be found from either language.
    private static func name(of language: AppLanguage) -> String {
        switch language {
        case .system: return Localizable.languageSystem.localized
        case .english: return "English"
        case .portuguese: return "Português (Brasil)"
        }
    }

    // MARK: - Experimental

    /// Features still being tried out. Only iOS 26 and later has the on-device speech model that
    /// Read-along needs, so earlier systems don't see the section at all. Turning the switch off
    /// deletes every transcript (`AppSettings.readAlongEnabled`).
    @available(iOS 26, *)
    private func experimentalSection(settings: Bindable<AppSettings>) -> some View {
        Section {
            Toggle(Localizable.readAlongToggle.localized, isOn: settings.readAlongEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.readAlong)
        } header: {
            Text(Localizable.experimentalTitle.localized)
        } footer: {
            Text(Localizable.readAlongFooter.localized)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            linkRow(Localizable.privacyPolicy.localized, url: Self.privacyPolicyURL)
                .accessibilityIdentifier(AccessibilityID.Settings.privacyPolicy)
            LabeledContent(Localizable.version.localized, value: model.versionText)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.Settings.version)
            linkRow("LibriVox", url: Self.libriVoxURL)
                .accessibilityIdentifier(AccessibilityID.Settings.librivox)
            NavigationLink(Localizable.openSourceLicenses.localized) {
                LicensesView()
            }
            .accessibilityIdentifier(AccessibilityID.Settings.licenses)
            NavigationLink(Localizable.aboutDeveloper.localized) {
                DeveloperView(openLinkedIn: { webPage = Self.linkedInURL.map(WebPage.init) })
            }
            .accessibilityIdentifier(AccessibilityID.Settings.developer)
            audioStatusRow
        } header: {
            Text(Localizable.settingsAbout.localized)
        } footer: {
            Text(Localizable.librivoxAbout.localized)
        }
    }

    private func linkRow(_ title: String, url: URL?) -> some View {
        Button {
            webPage = url.map(WebPage.init)
        } label: {
            HStack {
                Text(title)
                    .foregroundColor(ColorConstants.white.value)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(ColorConstants.spanishGray.value)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(.isLink)
    }

    /// Surfaces `LaunchStateFlag` (#115): when the audio session failed at launch every Siri
    /// intent answers "Audio temporarily unavailable", and nothing else in the app says so.
    private var audioStatusRow: some View {
        let isUnavailable = model.isAudioUnavailable
        return VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
            // An HStack, not `LabeledContent`: inside this VStack the latter stretches to fill the row.
            HStack {
                Text(Localizable.siriAudioStatus.localized)
                Spacer()
                Label(
                    isUnavailable ? Localizable.audioStatusUnavailable.localized : Localizable.audioStatusOK.localized,
                    systemImage: isUnavailable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundColor(isUnavailable ? ColorConstants.maximumRed.value : ColorConstants.malachite.value)
            }
            Text(
                isUnavailable
                    ? Localizable.audioStatusUnavailableDetail.localized
                    : Localizable.audioStatusOKDetail.localized
            )
                .font(.footnote)
                .foregroundColor(ColorConstants.lightSilver.value)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Settings.audioStatus)
    }

    /// The cellular setting's options and its value, in the in-app language.
    static func title(of preference: CellularDownloadPreference) -> String {
        switch preference {
        case .ask: Localizable.cellularAsk.localized
        case .always: Localizable.cellularAlways.localized
        case .wifiOnly: Localizable.cellularWifiOnly.localized
        }
    }
}

// MARK: - Pages

/// Settings' default speed page: the same control as the player's speed sheet.
private struct DefaultSpeedView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceConstants.sx16.value) {
                SpeedControlView(speed: settings.defaultSpeed) { settings.defaultSpeed = $0 }
                Text(Localizable.defaultSpeedFooter.localized)
                    .font(.footnote)
                    .foregroundColor(ColorConstants.lightSilver.value)
            }
            .padding(SpaceConstants.sx24.value)
        }
        .navigationTitle(Localizable.defaultSpeed.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Who makes Abbay: a short note and a button to the developer's LinkedIn.
private struct DeveloperView: View {
    let openLinkedIn: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceConstants.sx24.value) {
                Text(Localizable.developerBody.localized)
                    .foregroundColor(ColorConstants.white.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.Settings.developerBody)
                Button(action: openLinkedIn) {
                    Text(Localizable.developerLinkedIn.localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityAddTraits(.isLink)
                .accessibilityIdentifier(AccessibilityID.Settings.linkedIn)
            }
            .padding(SpaceConstants.sx24.value)
        }
        .navigationTitle(Localizable.aboutDeveloper.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What ships in the app: no third-party code, and public-domain audiobooks.
private struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceConstants.sx16.value) {
                Text(Localizable.licensesBody.localized)
                Text(Localizable.licensesContent.localized)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SpaceConstants.sx24.value)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.Settings.licensesBody)
        }
        .navigationTitle(Localizable.openSourceLicenses.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Web

private struct WebPage: Identifiable {
    let url: URL
    var id: URL { url }
}

/// In-app Safari, so the privacy policy and LibriVox open without leaving Abbay.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

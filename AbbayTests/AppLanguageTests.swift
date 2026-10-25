//
//  AppLanguageTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The app's own language: the in-app override from Settings, the pt-BR plurals that agree with
/// a count (#124), and the duration units that follow the app's language rather than the device's.
final class AppLanguageTests: XCTestCase {
    /// The test host is the real app, which applies the stored in-app language at launch. Start
    /// from no override, and leave none behind.
    override func setUpWithError() throws {
        try super.setUpWithError()
        AbbayBundle.languageCode = nil
    }

    override func tearDownWithError() throws {
        AbbayBundle.value.unsetLocalizedLanguage()
        AbbayBundle.languageCode = nil
        try super.tearDownWithError()
    }

    // MARK: - In-app language (Settings)

    func test_inAppLanguageOverride_readsThatLanguage_andNilFollowsTheDevice() {
        let deviceValue = Localizable.settingsTitle.localized

        AbbayBundle.languageCode = "pt-BR"
        XCTAssertEqual(Localizable.settingsTitle.localized, "Ajustes")
        XCTAssertEqual(Localizable.skipSeconds.localized(with: 30), "30 segundos")
        XCTAssertEqual(AbbayBundle.locale.identifier, "pt-BR")

        AbbayBundle.languageCode = "en"
        XCTAssertEqual(Localizable.settingsTitle.localized, "Settings")

        AbbayBundle.languageCode = nil
        XCTAssertEqual(Localizable.settingsTitle.localized, deviceValue)
    }

    /// Choosing a language in Settings applies it to the bundle at once, with no relaunch.
    func test_choosingALanguage_inSettings_switchesTheStrings() {
        let settings = AppSettings(store: InMemoryKeyValueStore(), effects: LiveSettingsEffects())

        settings.language = .portuguese
        XCTAssertEqual(Localizable.playbackSpeed.localized, "Velocidade de reprodução")

        settings.language = .english
        XCTAssertEqual(Localizable.playbackSpeed.localized, "Playback speed")
    }

    // MARK: - Plurals

    /// English "left" does not inflect, so the count is taken and ignored.
    func test_timeLeftStrings_inEnglish_readTheSameInSingularAndPlural() {
        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "1 min", 1), "1 min left")
        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "2 min", 2), "2 min left")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "1 min", 1), "Chapter 2 · 1 min left")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "2 min", 2), "Chapter 2 · 2 min left")
    }

    /// pt-BR reads "%@ restante(s)", not "faltam %@", which is wrong at one minute ("faltam 1 min"),
    /// and "restante" agrees with the count (#124).
    func test_timeLeftStrings_inPortuguese_agreeWithTheCount() {
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "1 min", 1), "1 min restante")
        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "2 min", 2), "2 min restantes")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "1 min", 1), "Capítulo 2 · 1 min restante")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "2 min", 2), "Capítulo 2 · 2 min restantes")
        XCTAssertEqual(Localizable.chapterProgress.localized, "Progresso do capítulo")
    }

    // MARK: - Units follow the app language

    /// The duration formatters take their locale from here, so it must track the in-app language
    /// override, not the device locale.
    func test_appLocale_followsTheInAppLanguage() {
        XCTAssertEqual(AbbayBundle.locale.identifier, "en")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(AbbayBundle.locale.identifier, "pt-BR")
    }

    /// One unit reads as singular, anything more as plural, and the units ("hr" / "h e") are in
    /// the same language as the sentence around them.
    func test_miniPlayerSubtitle_formatsUnitsInTheAppLanguage() {
        let book = AudioModel(duration: 10_000, chapters: [ChapterModel(startTime: 0, duration: 10_000)])

        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 9940), "Chapter 1 · 1 min left")
        XCTAssertEqual(
            MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 2740),
            "Chapter 1 · 2 hr, 1 min left"
        )

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(
            MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 9940),
            "Capítulo 1 · 1 min restante"
        )
        XCTAssertEqual(
            MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 9880),
            "Capítulo 1 · 2 min restantes"
        )
        XCTAssertEqual(
            MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 2740),
            "Capítulo 1 · 2 h e 1 min restantes"
        )
    }

    // MARK: - pt-BR edge cases (#152)

    /// CLDR puts 0 in Portuguese's "one" category, which read "0s restante". Nothing left is
    /// plural in Brazilian Portuguese ("0 minutos restantes"), so the strings carry a zero form.
    func test_zeroTimeLeft_inPortuguese_isPlural() {
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "0s", 0), "0s restantes")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 3, "0 min", 0), "Capítulo 3 · 0 min restantes")
        let finished = AudioModel(duration: 200)
        XCTAssertEqual(MediaView.detailLine(book: finished, chapterIndex: 0, bookTime: 200), "0s restantes")
    }

    func test_zeroTimeLeft_inEnglish_readsLeft() {
        XCTAssertEqual(MediaView.detailLine(book: AudioModel(duration: 200), chapterIndex: 0, bookTime: 200), "0s left")
    }

    /// Exactly one hour read "1 h e 0 min" ("1 hr, 0 min" in English): a zero minute is dropped,
    /// and one hour is singular.
    func test_miniPlayerSubtitle_exactlyOneHour_dropsTheZeroMinutes() {
        let book = AudioModel(duration: 5400, chapters: [
            ChapterModel(startTime: 0, duration: 3600),
            ChapterModel(startTime: 3600, duration: 1800)
        ])

        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 0), "Chapter 1 · 1 hr left")
        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 3540), "Chapter 1 · 1 min left")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 0), "Capítulo 1 · 1 h restante")
        let oneMinute = "Capítulo 1 · 1 min restante"
        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 3540), oneMinute)
        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 3570), oneMinute)
    }

    /// Two whole hours drop the zero minutes too, and stay plural.
    func test_miniPlayerSubtitle_wholeHours_inPortuguese_arePlural() {
        let book = AudioModel(duration: 7200, chapters: [ChapterModel(startTime: 0, duration: 7200)])
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 0), "Capítulo 1 · 2 h restantes")
    }

    /// At the very end of a chapter the mini player shows zero, not an empty string.
    func test_miniPlayerSubtitle_atTheChaptersEnd_showsZero() {
        let book = AudioModel(duration: 7200, chapters: [ChapterModel(startTime: 0, duration: 7200)])

        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 7200), "Chapter 1 · 0 min left")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        let zero = "Capítulo 1 · 0 min restantes"
        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 7200), zero)
    }

    // MARK: - Byte sizes follow the app language (#152, part of #166)

    /// "296,7 MB" showed in the English UI on a Portuguese device: `ByteCountFormatter` has no
    /// locale of its own and always uses the device's.
    func test_byteSize_usesTheAppLanguagesDecimalSeparator() {
        XCTAssertEqual(ByteSize.text(29_670_000, locale: Locale(identifier: "en")), "29.7 MB")
        XCTAssertEqual(ByteSize.text(29_670_000, locale: Locale(identifier: "pt-BR")), "29,7 MB")
    }

    func test_byteSize_defaultsToTheAppLanguage() {
        AbbayBundle.languageCode = "en"
        XCTAssertEqual(ByteSize.text(296_700_000), "296.7 MB")

        AbbayBundle.languageCode = "pt-BR"
        XCTAssertEqual(ByteSize.text(296_700_000), "296,7 MB")
    }

    /// Settings › Downloads (Space used, the delete confirmation) never reads in bytes.
    @MainActor
    func test_settingsSizes_followTheAppLanguage() {
        AbbayBundle.languageCode = "en"
        XCTAssertEqual(SettingsViewModel.formatted(bytes: 1_536_000), "1.5 MB")
        XCTAssertEqual(SettingsViewModel.formatted(bytes: 0), "Zero kB")

        AbbayBundle.languageCode = "pt-BR"
        XCTAssertEqual(SettingsViewModel.formatted(bytes: 1_536_000), "1,5 MB")
    }

    /// The LibriVox page's "· inglês" read in the device's language under an English UI.
    func test_libriVoxLanguageName_followsTheAppLanguage() {
        let book = LibriVoxBook(
            id: "x",
            title: "T",
            authors: "A",
            descriptionText: "",
            language: "eng",
            totalSeconds: 60,
            coverURL: URL(fileURLWithPath: "/dev/null"),
            sections: []
        )

        AbbayBundle.languageCode = "en"
        XCTAssertEqual(book.languageName, "English")

        AbbayBundle.languageCode = "pt-BR"
        XCTAssertEqual(book.languageName, "inglês")
    }

    func test_rowDetailLine_formatsUnitsInTheAppLanguage() {
        let book = AudioModel(duration: 3600)

        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 0), "1h left")
        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 3510), "1m 30s left")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 0), "1h restante")
        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 3540), "1min restante")
        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 3510), "1min 30s restantes")
    }
}

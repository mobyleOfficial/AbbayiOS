//
//  ReadAlongLanguageTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class ReadAlongLanguageTests: XCTestCase {
    // MARK: LibriVox labels

    func test_languageCode_fromThreeLetterCodes() {
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "eng"), "en")
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "por"), "pt")
    }

    func test_languageCode_fromBibliographicCodes() {
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "ger"), "de")
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "fre"), "fr")
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "dut"), "nl")
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "chi"), "zh")
    }

    func test_languageCode_fromEnglishNames_ignoringCaseAndSpaces() {
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "English"), "en")
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "Portuguese"), "pt")
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "German"), "de")
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: " german "), "de")
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "FRENCH"), "fr")
    }

    func test_languageCode_fromTwoLetterCode() {
        XCTAssertEqual(ReadAlongLanguage.languageCode(fromLibriVox: "pt"), "pt")
    }

    func test_languageCode_unknownOrEmpty_isNil() {
        XCTAssertNil(ReadAlongLanguage.languageCode(fromLibriVox: "Klingon"))
        XCTAssertNil(ReadAlongLanguage.languageCode(fromLibriVox: ""))
        XCTAssertNil(ReadAlongLanguage.languageCode(fromLibriVox: "   "))
        XCTAssertNil(ReadAlongLanguage.languageCode(fromLibriVox: "zzz"))
    }

    // MARK: candidates

    func test_candidates_appLanguage_thenDevice_thenEnglish() {
        let result = ReadAlongLanguage.candidates(
            appLanguage: "pt",
            preferred: ["pt-BR", "en-GB"],
            installed: ["en-US", "en-GB", "pt-BR"]
        )
        XCTAssertEqual(result, ["pt-BR", "en-GB", "en-US"])
    }

    func test_candidates_skipsWhatIsNotInstalled() {
        let result = ReadAlongLanguage.candidates(
            appLanguage: "pt",
            preferred: ["pt-BR", "fr-FR"],
            installed: ["en-US"]
        )
        XCTAssertEqual(result, ["en-US"])
    }

    func test_candidates_systemLanguage_usesPreferredOnly() {
        let result = ReadAlongLanguage.candidates(
            appLanguage: nil,
            preferred: ["pt-BR"],
            installed: ["pt-BR", "pt-PT", "en-US"]
        )
        XCTAssertEqual(result, ["pt-BR", "en-US"])
    }

    func test_candidates_bareAppLanguage_takesTheRegionOfTheMatchingPreferredEntry() {
        let result = ReadAlongLanguage.candidates(
            appLanguage: "pt",
            preferred: ["pt-BR"],
            installed: ["pt-PT", "pt-BR", "en-US"]
        )
        XCTAssertEqual(result, ["pt-BR", "en-US"])
    }

    func test_candidates_preferredRegionNotInstalled_fallsBackToItsLanguage() {
        let result = ReadAlongLanguage.candidates(
            appLanguage: nil,
            preferred: ["pt-BR"],
            installed: ["pt-PT", "en-US"]
        )
        XCTAssertEqual(result, ["pt-PT", "en-US"])
    }

    func test_candidates_normalisesUnderscoresFromSpeech() {
        let result = ReadAlongLanguage.candidates(
            appLanguage: "pt",
            preferred: ["pt_BR", "en_GB"],
            installed: ["en_US", "en_GB", "pt_BR"]
        )
        XCTAssertEqual(result, ["pt-BR", "en-GB", "en-US"])
    }

    func test_candidates_english_prefersUSThenAnyEnglish() {
        XCTAssertEqual(
            ReadAlongLanguage.candidates(appLanguage: nil, preferred: [], installed: ["en-AU", "en-US"]),
            ["en-US"]
        )
        XCTAssertEqual(
            ReadAlongLanguage.candidates(appLanguage: nil, preferred: [], installed: ["en-AU", "en-GB"]),
            ["en-AU"]
        )
    }

    func test_candidates_nothingInstalled_isEmpty() {
        XCTAssertEqual(
            ReadAlongLanguage.candidates(appLanguage: "pt", preferred: ["pt-BR"], installed: []),
            []
        )
    }

    // MARK: best

    func test_best_picksTheMostConfident() {
        XCTAssertEqual(ReadAlongLanguage.best(["en-US": 0.9, "pt-BR": 0.4]), "en-US")
    }

    func test_best_belowMinimum_isNil() {
        XCTAssertNil(ReadAlongLanguage.best(["en-US": 0.3]))
    }

    func test_best_atTheMinimum_counts() {
        XCTAssertEqual(ReadAlongLanguage.best(["en-US": 0.5]), "en-US")
    }

    func test_best_empty_isNil() {
        XCTAssertNil(ReadAlongLanguage.best([:]))
    }

    func test_best_customMinimum() {
        XCTAssertNil(ReadAlongLanguage.best(["en-US": 0.7], minimumConfidence: 0.8))
    }

    func test_best_tie_isDeterministic() {
        XCTAssertEqual(ReadAlongLanguage.best(["pt-BR": 0.8, "en-US": 0.8]), "en-US")
    }

    // MARK: locale(forLanguageCode:)

    func test_locale_matchesPreferredRegion() {
        XCTAssertEqual(
            ReadAlongLanguage.locale(forLanguageCode: "pt", in: ["pt-BR", "pt-PT", "en-US"], preferredRegion: "BR"),
            "pt-BR"
        )
        XCTAssertEqual(
            ReadAlongLanguage.locale(forLanguageCode: "pt", in: ["pt-BR", "pt-PT", "en-US"], preferredRegion: "PT"),
            "pt-PT"
        )
    }

    func test_locale_noRegion_firstMatch() {
        XCTAssertEqual(
            ReadAlongLanguage.locale(forLanguageCode: "pt", in: ["pt-BR", "pt-PT", "en-US"], preferredRegion: nil),
            "pt-BR"
        )
    }

    func test_locale_regionNotOffered_firstOfTheLanguage() {
        XCTAssertEqual(
            ReadAlongLanguage.locale(forLanguageCode: "pt", in: ["en-US", "pt-PT"], preferredRegion: "BR"),
            "pt-PT"
        )
    }

    func test_locale_noMatch_isNil() {
        XCTAssertNil(ReadAlongLanguage.locale(forLanguageCode: "de", in: ["pt-BR", "en-US"], preferredRegion: nil))
    }

    func test_locale_normalisesUnderscores() {
        XCTAssertEqual(
            ReadAlongLanguage.locale(forLanguageCode: "pt", in: ["pt_BR"], preferredRegion: "BR"),
            "pt-BR"
        )
    }

    // MARK: displayName

    func test_displayName_isInTheGivenLocale() {
        let english = Locale(identifier: "en")
        let portuguese = Locale(identifier: "pt-BR")
        XCTAssertEqual(ReadAlongLanguage.displayName("en-US", in: english), "English")
        XCTAssertEqual(ReadAlongLanguage.displayName("pt-BR", in: english), "Portuguese")
        XCTAssertEqual(ReadAlongLanguage.displayName("pt-BR", in: portuguese), "Português")
        XCTAssertEqual(ReadAlongLanguage.displayName("en_US", in: portuguese), "Inglês")
    }

    func test_displayName_unknown_fallsBackToTheIdentifier() {
        XCTAssertEqual(ReadAlongLanguage.displayName("zzz", in: Locale(identifier: "en")), "zzz")
    }
}

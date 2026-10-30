//
//  ReadAlongViewTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The read-along square's language menu: each choice named by its language, with the region only
/// where two choices share a language, in the in-app language.
final class ReadAlongViewTests: XCTestCase {
    private let english = Locale(identifier: "en")
    private let portuguese = Locale(identifier: "pt-BR")

    func test_languageChoices_differentLanguages_areNamedByLanguageAlone() {
        let choices = ReadAlongView.languageChoices(["pt-BR", "en-US"], in: english)

        XCTAssertEqual(choices.map(\.name), ["English", "Portuguese"])
        XCTAssertEqual(choices.map(\.id), ["en-US", "pt-BR"], "sorted by name, ids kept")
    }

    func test_languageChoices_sharedLanguage_carriesTheRegion() {
        let choices = ReadAlongView.languageChoices(["en-US", "en-GB", "fr-FR"], in: english)

        XCTAssertEqual(choices.map(\.name), ["English (United Kingdom)", "English (United States)", "French"])
    }

    func test_languageChoices_areNamedInTheInAppLanguage_andTakeUnderscoredIds() {
        let choices = ReadAlongView.languageChoices(["pt_BR", "pt_PT", "en_US"], in: portuguese)

        XCTAssertEqual(choices.first?.name, "Inglês")
        XCTAssertEqual(choices.count, 3)
        XCTAssertTrue(choices.dropFirst().allSatisfy { $0.name.hasPrefix("Português (") }, "\(choices)")
        XCTAssertEqual(Set(choices.map(\.id)), ["pt_BR", "pt_PT", "en_US"])
    }
}

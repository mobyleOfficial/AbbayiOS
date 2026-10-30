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

    // MARK: - The session slot

    @MainActor
    private func makeCenter() -> ReadAlongCenter {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return ReadAlongCenter(
            transcriber: StubReadAlongTranscriber(),
            store: ReadAlongStore(root: root),
            settings: AppSettings(store: InMemoryKeyValueStore())
        )
    }

    /// The square is rebuilt on each flip and rotation; the session it shows must be the same one,
    /// so its language, model check and transcript aren't redone.
    @MainActor
    func test_sessionSlot_handsOutOneSession() {
        let center = makeCenter()
        let slot = ReadAlongSessionSlot()

        let first = slot.session(from: center)
        let second = slot.session(from: center)

        XCTAssertTrue(first === second)
        XCTAssertFalse(first === ReadAlongSessionSlot().session(from: center), "one session per screen")
    }

    /// In a rotation the new square can appear before the old one disappears: only the last one to
    /// go stops the session.
    @MainActor
    func test_sessionSlot_stopsOnlyWhenNoSquareShowsIt() {
        let slot = ReadAlongSessionSlot()

        slot.appeared()
        slot.appeared()

        XCTAssertFalse(slot.disappeared(), "the new square still shows it")
        XCTAssertTrue(slot.disappeared(), "the last square went")
        XCTAssertTrue(slot.disappeared(), "an extra disappearance doesn't go negative")
        slot.appeared()
        XCTAssertTrue(slot.disappeared())
    }

    // MARK: - Scrubbing

    /// The square starts no run while a finger is on the scrubber, and starts one as soon as it
    /// lifts: the scrubbed time stays shown until the seek lands, but the drag is over at once.
    @MainActor
    func test_scrub_isDraggingOnlyWhileTheFingerIsDown_whileItsTimeOutlivesTheDrag() {
        let scrub = PlayerScrub()
        XCTAssertFalse(scrub.isDragging)

        scrub.drag(to: 120)
        XCTAssertTrue(scrub.isDragging)
        XCTAssertEqual(scrub.time, 120)

        scrub.finish()
        XCTAssertFalse(scrub.isDragging)
        XCTAssertEqual(scrub.time, 120, "shown until the seek lands")
    }

    // MARK: - VoiceOver

    /// A line seeks when tapped, so VoiceOver says so, in both languages.
    func test_lineHint_isTranslated() {
        defer {
            AbbayBundle.value.unsetLocalizedLanguage()
            AbbayBundle.languageCode = nil
        }
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "en"))
        XCTAssertEqual(Localizable.readAlongLineHint.localized, "Plays from this line")
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))
        XCTAssertEqual(Localizable.readAlongLineHint.localized, "Toca a partir desta linha")
    }
}

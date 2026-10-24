//
//  IntentDonorTests.swift
//  AbbayTests
//

@testable import Abbay
import Intents
import XCTest

final class IntentDonorTests: XCTestCase {
    func test_buildIntent_constructsExpectedShape() {
        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        model.title = "Harry Potter"

        let donor = IntentDonor()
        let intent = donor.buildIntent(for: model)

        XCTAssertEqual(intent.mediaItems?.first?.title, "Harry Potter")
        XCTAssertEqual(intent.mediaItems?.first?.type, .audioBook)
        XCTAssertEqual(intent.mediaItems?.first?.identifier, "file:///book.m4a")
        XCTAssertEqual(intent.mediaSearch?.mediaName, "Harry Potter")
        XCTAssertEqual(intent.mediaSearch?.mediaType, .audioBook)
    }
}

/// Donations on play, on pause and at chapter boundaries (#127), with repeats for the same book
/// inside `repeatWindow` dropped.
final class IntentDonorRepeatTests: XCTestCase {
    private var now = Date(timeIntervalSinceReferenceDate: 0)
    private var donatedTitles: [String] = []

    private func makeDonor() -> IntentDonor {
        IntentDonor(
            now: { [unowned self] in self.now },
            donate: { [unowned self] interaction, _ in
                let intent = interaction.intent as? INPlayMediaIntent
                self.donatedTitles.append(intent?.mediaItems?.first?.title ?? "")
            }
        )
    }

    private func book(_ title: String) -> AudioModel {
        AudioModel(title: title, url: URL(string: "file:///\(title).m4b"))
    }

    func test_sameBookInsideTheWindow_isDonatedOnce() {
        let donor = makeDonor()

        donor.donatePlayMedia(model: book("One"))
        now = now.addingTimeInterval(IntentDonor.repeatWindow - 1)
        donor.donatePlayMedia(model: book("One"))

        XCTAssertEqual(donatedTitles, ["One"])
    }

    func test_sameBookAfterTheWindow_isDonatedAgain() {
        let donor = makeDonor()

        donor.donatePlayMedia(model: book("One"))
        now = now.addingTimeInterval(IntentDonor.repeatWindow)
        donor.donatePlayMedia(model: book("One"))

        XCTAssertEqual(donatedTitles, ["One", "One"])
    }

    func test_anotherBookInsideTheWindow_isDonated() {
        let donor = makeDonor()

        donor.donatePlayMedia(model: book("One"))
        donor.donatePlayMedia(model: book("Two"))
        donor.donatePlayMedia(model: book("One"))

        XCTAssertEqual(donatedTitles, ["One", "Two", "One"])
    }

    /// A dropped repeat doesn't extend the window: listening donates again once it has passed.
    func test_droppedRepeat_doesNotRestartTheWindow() {
        let donor = makeDonor()

        donor.donatePlayMedia(model: book("One"))
        now = now.addingTimeInterval(IntentDonor.repeatWindow - 1)
        donor.donatePlayMedia(model: book("One"))
        now = now.addingTimeInterval(1)
        donor.donatePlayMedia(model: book("One"))

        XCTAssertEqual(donatedTitles, ["One", "One"])
    }
}

/// A donation's outcome reaches the unified log (#157): a failure with its public error domain and
/// code, never the book's title.
final class IntentDonorLoggingTests: XCTestCase {
    private func book(_ title: String) -> AudioModel {
        AudioModel(title: title, url: URL(string: "file:///\(title).m4b"))
    }

    func test_donation_passesACompletionHandler_andLogsAFailure_withoutTheTitle() throws {
        let since = Date()
        var completion: ((Error?) -> Void)?
        let donor = IntentDonor(donate: { _, handler in completion = handler })

        donor.donatePlayMedia(model: book("SecretTitle157"))
        try XCTUnwrap(completion, "the donation must be given a completion handler")(
            NSError(domain: "IntentsErrorDomain", code: 1901)
        )

        let messages = try LoggedMessages.messages(category: "Siri", since: since)
        let failure = try XCTUnwrap(messages.first { $0.contains("donation failed") }, "\(messages)")
        XCTAssertTrue(failure.contains("IntentsErrorDomain"), failure)
        XCTAssertTrue(failure.contains("1901"), failure)
        XCTAssertFalse(messages.contains { $0.contains("SecretTitle157") }, "\(messages)")
    }

    func test_successfulDonation_logsNoFailure() throws {
        let since = Date()
        let donor = IntentDonor(donate: { _, handler in handler(nil) })

        donor.donatePlayMedia(model: book("Fine"))

        let messages = try LoggedMessages.messages(category: "Siri", since: since)
        XCTAssertFalse(messages.contains { $0.contains("donation failed") }, "\(messages)")
    }
}

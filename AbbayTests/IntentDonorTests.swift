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

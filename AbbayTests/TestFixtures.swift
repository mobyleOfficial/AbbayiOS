//
//  TestFixtures.swift
//  AbbayTests
//

import Foundation
import XCTest

/// Access to the committed audiobook fixture. See `Fixtures/README.md` for provenance.
enum TestFixtures {
    static let chapterCount = 4
    static let duration: Double = 831.6
    /// Chapter starts in `Christmastide.m4b`, in seconds.
    static let chapterStarts: [Double] = [0, 144.015, 288.012, 511.021]

    static func christmastideURL(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        try XCTUnwrap(
            Bundle(for: FixtureBundleAnchor.self)
                .url(forResource: "Christmastide", withExtension: "m4b"),
            "Fixtures/Christmastide.m4b is missing from the test bundle. It is declared as a "
                + "resource in project.yml; re-run `bundle exec fastlane generate_project`.",
            file: file,
            line: line
        )
    }
}

/// `Bundle(for:)` needs a class in the test bundle; this is that class and nothing more.
private final class FixtureBundleAnchor {}

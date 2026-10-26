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

extension TestFixtures {
    /// Bytes of `Fixtures/LibriVox/<name>.json`. XcodeGen flattens resource folders, so the file may sit
    /// at the bundle root or in a `LibriVox` subdirectory.
    static func librivoxData(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Data {
        let bundle = Bundle(for: FixtureBundleAnchor.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "LibriVox"),
            "Fixtures/LibriVox/\(name).json is missing from the test bundle.",
            file: file,
            line: line
        )
        return try Data(contentsOf: url)
    }
}

/// `Bundle(for:)` needs a class in the test bundle; this is that class and nothing more.
private final class FixtureBundleAnchor {}

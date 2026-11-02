//
//  RenameBookUITests.swift
//  AbbayUITests
//

import XCTest

/// Renaming an imported book (#322): the ✎ beside the player's title and the library cell's menu
/// open *Rename book*; the new name shows in the player and the library, and an empty one gives
/// the book back its file's name (*Seeded Plain Book*'s file is `plain.m4b`).
final class RenameBookUITests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [LaunchArgument.seedLibrary, LaunchArgument.resetSettings]
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20), "no library")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func rowIndex(titled title: String) -> Int? {
        (0..<6).first { index in
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            return candidate.exists && candidate.label == title
        }
    }

    /// Types `name` into the open *Rename book* box, replacing what is there, and saves.
    private func rename(to name: String, file: StaticString = #filePath, line: UInt = #line) {
        // An alert: its text field and buttons don't carry SwiftUI's identifiers.
        let box = app.alerts["Rename book"]
        XCTAssertTrue(box.waitForExistence(timeout: 5), "no Rename book box", file: file, line: line)
        let field = box.textFields.firstMatch
        field.tap()
        if let current = field.value as? String, !current.isEmpty, current != "Book name" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        if !name.isEmpty { field.typeText(name) }
        box.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(box.waitForNonExistence(timeout: 5), "the box stayed", file: file, line: line)
    }

    func test_renameFromThePlayer_showsInThePlayerAndTheLibrary() throws {
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Plain Book"), "no plain seed")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        let pencil = element(AccessibilityID.Player.rename)
        XCTAssertTrue(pencil.waitForExistence(timeout: 15), "no ✎ beside an imported book's title")

        pencil.tap()
        rename(to: "The Plain Story")

        let title = element(AccessibilityID.Player.title)
        let deadline = Date().addingTimeInterval(5)
        while title.label != "The Plain Story", Date() < deadline { usleep(100_000) }
        XCTAssertEqual(title.label, "The Plain Story")
        element(AccessibilityID.Player.close).tap()
        XCTAssertNotNil(rowIndex(titled: "The Plain Story"), "the library row kept the old name")
    }

    func test_renameFromTheLibraryMenu_emptyGivesBackTheFilesName() throws {
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Plain Book"), "no plain seed")
        LibraryGridActions.openMenu(in: app, cell: index)
        let item = element(AccessibilityID.Element.rename(AccessibilityID.Library.row(index)))
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the cell's menu has no Rename")

        item.tap()
        rename(to: "")

        let deadline = Date().addingTimeInterval(5)
        while rowIndex(titled: "plain") == nil, Date() < deadline { usleep(200_000) }
        XCTAssertNotNil(rowIndex(titled: "plain"), "an empty name didn't give back the file's name")
    }
}

//
//  LibraryGridActions.swift
//  AbbayUITests
//

import XCTest

/// The library grid's per-book actions live in each cell's context menu (#166 G3): Play / Pause
/// (`library.row.N.play`) and Delete (`library.row.N.delete`). The items exist only while the
/// menu is open, so tests open it with a long press on the cell's title first.
enum LibraryGridActions {
    private static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Long-presses cell `index` and returns its menu's Play / Pause item, waiting for it.
    @discardableResult
    static func openMenu(
        in app: XCUIApplication,
        cell index: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let namespace = AccessibilityID.Library.row(index)
        let title = element(app, AccessibilityID.Element.title(namespace))
        XCTAssertTrue(title.waitForExistence(timeout: 15), "no cell \(index)", file: file, line: line)
        title.press(forDuration: 1.2)
        let play = element(app, AccessibilityID.Element.play(namespace))
        XCTAssertTrue(play.waitForExistence(timeout: 5), "cell \(index)'s menu has no Play/Pause", file: file, line: line)
        return play
    }

    /// Plays (or pauses) cell `index` from its context menu.
    static func togglePlayback(in app: XCUIApplication, cell index: Int, file: StaticString = #filePath, line: UInt = #line) {
        openMenu(in: app, cell: index, file: file, line: line).tap()
    }

    /// The label of cell `index`'s Play / Pause menu item ("Play" or "Pause"); the menu is closed
    /// again afterwards.
    static func playbackItemLabel(in app: XCUIApplication, cell index: Int) -> String {
        let item = openMenu(in: app, cell: index)
        let label = item.label
        dismissMenu(in: app, item: item)
        return label
    }

    /// Deletes cell `index` from its context menu.
    static func delete(in app: XCUIApplication, cell index: Int, file: StaticString = #filePath, line: UInt = #line) {
        openMenu(in: app, cell: index, file: file, line: line)
        let delete = element(app, AccessibilityID.Element.delete(AccessibilityID.Library.row(index)))
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "cell \(index)'s menu has no Delete", file: file, line: line)
        delete.tap()
    }

    /// A tap at the top of the screen, off the menu, closes it.
    static func dismissMenu(in app: XCUIApplication, item: XCUIElement) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        _ = item.waitForNonExistence(timeout: 5)
    }
}

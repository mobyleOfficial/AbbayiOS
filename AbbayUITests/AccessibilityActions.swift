//
//  AccessibilityActions.swift
//  AbbayUITests
//

import XCTest

/// Performs an element's accessibility actions the way VoiceOver does, which XCUITest has no
/// public API for: `tap()` is a synthesized touch, not `accessibilityActivate()`, and there is
/// nothing at all for custom actions or the escape scrub.
///
/// This goes through XCTest's private accessibility client (`XCUIDevice.accessibilityInterface`,
/// an `XCAXClient_iOS`), with the AX action numbers VoiceOver itself sends: 2010 activate, 2013
/// escape, 2021 a custom action whose value is its `CustomActionIdentifier` dictionary. Test
/// code only, never shipped. If an Xcode release moves any of it, `AccessibilityActionError`
/// says which piece is missing, rather than a test silently doing nothing.
enum AccessibilityActions {
    private enum Action: Int {
        case activate = 2010
        case escape = 2013
        case custom = 2021
    }

    /// The custom actions' names, in the order VoiceOver lists them.
    static func customActionNames(of element: XCUIElement) throws -> [String] {
        try customActions(of: element).compactMap { $0["CustomActionName"] as? String }
    }

    /// The default action: what a VoiceOver double tap does.
    static func activate(_ element: XCUIElement) throws {
        try perform(.activate, value: nil, on: element)
    }

    /// The two-finger scrub ("Z"), sent to `element`; UIKit walks up from it to the first
    /// container that handles `accessibilityPerformEscape`.
    static func escape(from element: XCUIElement) throws {
        try perform(.escape, value: nil, on: element)
    }

    /// The custom action called `name`, as picked from VoiceOver's actions rotor.
    static func performCustomAction(named name: String, on element: XCUIElement) throws {
        let action = try customActions(of: element).first { $0["CustomActionName"] as? String == name }
        guard let action else {
            throw AccessibilityActionError("no custom action named \"\(name)\" on \(element)")
        }
        try perform(.custom, value: action as NSDictionary, on: element)
    }

    // MARK: - Private API

    private static let customActionsAttribute = "XC_kAXXCAttributeCustomActions"

    private static func customActions(of element: XCUIElement) throws -> [[String: Any]] {
        let interface = try accessibilityInterface()
        let target = try axElement(of: element)
        let selector = NSSelectorFromString("attributesForElement:attributes:error:")
        guard interface.responds(to: selector) else {
            throw AccessibilityActionError("XCAXClient_iOS has no \(selector)")
        }
        typealias Fetch = @convention(c) (
            AnyObject, Selector, AnyObject, NSArray, UnsafeMutablePointer<NSError?>?
        ) -> NSDictionary?
        let fetch = unsafeBitCast(interface.method(for: selector), to: Fetch.self)
        var error: NSError?
        let attributes = fetch(interface, selector, target, [customActionsAttribute] as NSArray, &error)
        if let error { throw error }
        return attributes?[customActionsAttribute] as? [[String: Any]] ?? []
    }

    private static func perform(_ action: Action, value: AnyObject?, on element: XCUIElement) throws {
        let interface = try accessibilityInterface()
        let target = try axElement(of: element)
        guard let actionClass = NSClassFromString("XCUIAccessibilityAction") as? NSObject.Type else {
            throw AccessibilityActionError("no XCUIAccessibilityAction class")
        }
        let initSelector = NSSelectorFromString("initWithAXAction:")
        typealias Make = @convention(c) (AnyObject, Selector, Int) -> AnyObject
        let allocated = actionClass.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        guard allocated.responds(to: initSelector) else {
            throw AccessibilityActionError("XCUIAccessibilityAction has no \(initSelector)")
        }
        let make = unsafeBitCast(allocated.method(for: initSelector), to: Make.self)
        let axAction = make(allocated, initSelector, action.rawValue)

        let selector = NSSelectorFromString("performAction:onElement:value:error:")
        guard interface.responds(to: selector) else {
            throw AccessibilityActionError("XCAXClient_iOS has no \(selector)")
        }
        typealias Perform = @convention(c) (
            AnyObject, Selector, AnyObject, AnyObject, AnyObject?, UnsafeMutablePointer<NSError?>?
        ) -> Bool
        let performAction = unsafeBitCast(interface.method(for: selector), to: Perform.self)
        var error: NSError?
        let handled = performAction(interface, selector, axAction, target, value, &error)
        if let error { throw error }
        guard handled else {
            throw AccessibilityActionError("AX action \(action.rawValue) was not handled by \(element)")
        }
    }

    private static func accessibilityInterface() throws -> AnyObject {
        let device = XCUIDevice.shared as NSObject
        guard device.responds(to: NSSelectorFromString("accessibilityInterface")),
              let interface = device.value(forKey: "accessibilityInterface") as AnyObject? else {
            throw AccessibilityActionError("XCUIDevice has no accessibilityInterface")
        }
        return interface
    }

    private static func axElement(of element: XCUIElement) throws -> AnyObject {
        guard let snapshot = try element.snapshot() as? NSObject,
              snapshot.responds(to: NSSelectorFromString("accessibilityElement")),
              let target = snapshot.value(forKey: "accessibilityElement") as AnyObject? else {
            throw AccessibilityActionError("\(element) has no accessibility element in its snapshot")
        }
        return target
    }
}

struct AccessibilityActionError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

//
//  BundleLocalization.swift
//  AbbayTests
//

import Foundation
import ObjectiveC

/// Swaps a bundle's localization at runtime so one test process can assert several languages.
///
/// Ported from the TestSupport module used in a sibling project. `NSLocalizedString` resolves
/// against the bundle's own preferred localization, which is fixed for the life of the process,
/// so the only way to exercise a second language in-process is to re-class the bundle and
/// forward `localizedString(forKey:value:table:)` to a specific `.lproj`.
extension Bundle {
    /// Returns false when the language has no compiled `.lproj`, so a test can fail loudly
    /// rather than silently asserting against the default language.
    @discardableResult
    func setLocalizedLanguage(to language: String) -> Bool {
        guard let path = path(forResource: language, ofType: "lproj"),
              let languageBundle = Bundle(path: path) else { return false }
        object_setClass(self, CustomLocalizedBundle.self)
        objc_setAssociatedObject(
            self,
            &Bundle.bundleKey,
            languageBundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return true
    }

    func unsetLocalizedLanguage() {
        objc_setAssociatedObject(self, &Bundle.bundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private extension Bundle {
    static var bundleKey: UInt8 = 0

    final class CustomLocalizedBundle: Bundle, @unchecked Sendable {
        override func localizedString(
            forKey key: String,
            value: String?,
            table tableName: String?
        ) -> String {
            guard let override = objc_getAssociatedObject(self, &Bundle.bundleKey) as? Bundle else {
                return super.localizedString(forKey: key, value: value, table: tableName)
            }
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
    }
}

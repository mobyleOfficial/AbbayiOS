//
//  LocalizedStringResourceResolution.swift
//  AbbayTests
//

import Foundation

extension LocalizedStringResource {
    /// Resolves the resource the way Siri does: in an explicit locale, not the test process's.
    ///
    /// Siri receives the resource itself and resolves it in the user's Siri language, so this is
    /// the faithful check. It needs no bundle swizzling (unlike `setLocalizedLanguage(to:)`),
    /// because the locale travels on the resource.
    func resolved(in identifier: String) -> String {
        var resource = self
        resource.locale = Locale(identifier: identifier)
        return String(localized: resource)
    }
}

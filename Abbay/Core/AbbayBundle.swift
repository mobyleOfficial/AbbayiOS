//
//  AbbayBundle.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/04/24.
//

import Foundation

final class AbbayBundle {
    static var value: Bundle {
        Bundle(for: Self.self)
    }

    /// The locale of the language the app's strings resolve in, for formatters (durations) whose
    /// units must match the sentence around them rather than the device locale.
    ///
    /// Read from the string table itself (`localeIdentifier`), so it follows any in-app language
    /// override on `value` the same way every `Localizable` string does. Falls back to the
    /// device locale if the key is missing.
    static var locale: Locale {
        let key = "localeIdentifier"
        let identifier = NSLocalizedString(key, bundle: value, comment: String())
        return identifier == key ? .current : Locale(identifier: identifier)
    }
}

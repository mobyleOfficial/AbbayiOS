//
//  ByteSize.swift
//  Abbay
//

import Foundation

/// File sizes ("29.7 MB", "29,7 MB") in the app's language.
///
/// `ByteCountFormatter` has no locale and always formats in the device's, so the English UI on a
/// Portuguese device read "296,7 MB" (#152, #166). The format style takes a locale.
enum ByteSize {
    /// - Parameter allowedUnits: `.all` picks the unit that fits, like `ByteCountFormatter`'s default.
    static func text(
        _ bytes: Int64,
        allowedUnits: ByteCountFormatStyle.Units = .all,
        locale: Locale = AbbayBundle.locale
    ) -> String {
        bytes.formatted(.byteCount(style: .file, allowedUnits: allowedUnits).locale(locale))
    }
}

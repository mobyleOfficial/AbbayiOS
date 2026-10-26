//
//  TimeLeftText.swift
//  Abbay
//

import Foundation

/// A formatted time left ("12 min", "1h 30m") and the count a "left" / "restante(s)" next to it
/// agrees with (#124).
struct TimeLeftText {
    let text: String
    /// 0 when the text reads as zero ("0s", "0 min"; the string table's `zero` form, plural in
    /// pt-BR), 1 when it reads as exactly one unit ("1 min", "1h", "1s"), otherwise the whole
    /// seconds. Only those categories matter to the string table, and comparing against the
    /// formatter's own output keeps that right whatever it rounds or drops.
    let count: Int

    /// Formats in the app's language (`AbbayBundle.locale`), not the device's, so the units match
    /// the sentence. Formatters are shared statics, so callers stay on the main thread.
    init(seconds: Double, formatter: DateComponentsFormatter) {
        var calendar = Calendar.current
        calendar.locale = AbbayBundle.locale
        formatter.calendar = calendar

        let text = formatter.string(from: seconds) ?? ""
        let oneUnit: [Double] = [1, 60, 3600]
        self.text = text
        if seconds <= 0 || text == formatter.string(from: 0) {
            // Zero first: a minutes-only formatter shows 1 s as "0 min", which would otherwise
            // match the one-unit check and read "0 min restante" (#152).
            count = 0
        } else {
            count = oneUnit.contains { formatter.string(from: $0) == text } ? 1 : Int(seconds)
        }
    }
}

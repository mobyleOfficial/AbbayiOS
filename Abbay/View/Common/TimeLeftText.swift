//
//  TimeLeftText.swift
//  Abbay
//

import Foundation

/// A formatted time left ("12 min", "1h 30m") and the count a "left" / "restante(s)" next to it
/// agrees with (#124).
struct TimeLeftText {
    let text: String
    /// 1 when the text reads as exactly one unit ("1 min", "1h", "1s"), otherwise the whole
    /// seconds. Only the singular/plural split matters to the string table, and comparing against
    /// the formatter's own one-unit output keeps that right whatever it rounds or drops.
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
        count = oneUnit.contains { formatter.string(from: $0) == text } ? 1 : Int(max(seconds, 0))
    }
}

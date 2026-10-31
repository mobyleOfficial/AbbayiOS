//
//  SettingsValues.swift
//  Abbay
//

import Foundation

/// Playback speed: the range, step and presets of the Android app's speed sheet (`SpeedSteps`).
enum PlaybackSpeed {
    static let minimum: Double = 0.5
    static let maximum: Double = 3.5
    static let step: Double = 0.05
    static let normal: Double = 1
    static let presets: [Double] = [0.8, 1, 1.2, 1.5, 1.75, 2, 2.5]

    /// Clamps to the range and rounds to the nearest step, without float drift (1.2, not
    /// 1.2000001), so equal-looking speeds compare equal. NaN is normal speed.
    static func snap(_ value: Double) -> Double {
        guard value.isFinite else { return normal }
        let clamped = min(max(value, minimum), maximum)
        let steps = (clamped / step).rounded()
        return (steps * step * 100).rounded() / 100
    }

    /// `speed` moved by `count` steps (the sheet's − and + buttons), kept in range.
    static func stepped(_ speed: Double, by count: Int) -> Double {
        snap(speed + Double(count) * step)
    }

    /// The preset after `speed`, wrapping from the fastest to the slowest: what one tap of
    /// CarPlay's rate button picks (#150). A speed between presets goes to the next one up.
    static func nextPreset(after speed: Double) -> Double {
        let current = snap(speed)
        return presets.first { $0 > current + step / 2 } ?? presets[0]
    }

    /// "1.0×", "1.25×", "1,5×" in Portuguese: one or two decimals, the locale's separator.
    static func label(_ speed: Double, locale: Locale = AbbayBundle.locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: speed)) ?? String(speed)
        return "\(number)×"
    }
}

/// Abbay's own volume: a gain on its player, under the system volume, never the system volume
/// itself. On the Mac the book can sit below a call, which the system volume would dim too.
enum BookVolume {
    static let minimum: Double = 0
    static let maximum: Double = 1
    static let step: Double = 0.05
    static let full: Double = 1

    /// Clamps to 0–1 and rounds to the nearest 5%, without float drift. NaN is full volume:
    /// a bad value must never silence the book.
    static func snap(_ value: Double) -> Double {
        guard value.isFinite else { return full }
        let clamped = min(max(value, minimum), maximum)
        let steps = (clamped / step).rounded()
        return (steps * step * 100).rounded() / 100
    }

    /// `volume` moved by `count` steps (VoiceOver's swipe up and down), kept in range.
    static func stepped(_ volume: Double, by count: Int) -> Double {
        snap(volume + Double(count) * step)
    }

    /// "60%": a whole percent, in the locale's format.
    static func label(_ volume: Double, locale: Locale = AbbayBundle.locale) -> String {
        snap(volume).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// The speaker on the volume pill: crossed out only at zero. Otherwise three waves, drawn with
    /// the level as the symbol's variable value, so they fill in by thirds at a constant width.
    static func symbol(_ volume: Double) -> String {
        snap(volume) == minimum ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }
}

/// How far the skip buttons jump, on screen, on the lock screen and in CarPlay.
enum SkipInterval: Int, CaseIterable, Identifiable {
    case ten = 10
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45

    /// What the app used everywhere before the setting existed.
    static let standard: SkipInterval = .fifteen

    var id: Int { rawValue }

    var seconds: Double { Double(rawValue) }

    /// SF Symbols draw the number inside the arrow, so the icon always shows the real amount.
    var backwardSymbol: String { "gobackward.\(rawValue)" }
    var forwardSymbol: String { "goforward.\(rawValue)" }
}

/// What starting a large LibriVox download on cellular does. Small books (at or under
/// `CellularDownloadPolicy.largeDownloadThreshold`) always download on any network.
enum CellularDownloadPreference: String, CaseIterable, Identifiable {
    /// The per-book "Continue / Wait for Wi-Fi" prompt (the behaviour before the setting).
    case ask
    /// Start on cellular without asking.
    case always
    /// Start Wi-Fi only without asking; the download waits for Wi-Fi.
    case wifiOnly

    var id: String { rawValue }
}

/// The app's language. `system` follows the device; the others override it in the app only.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case portuguese

    var id: String { rawValue }

    /// The `.lproj` to read strings from; nil follows the device.
    var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .portuguese: return "pt-BR"
        }
    }

    init?(languageCode: String) {
        guard let match = Self.allCases.first(where: { $0.languageCode == languageCode }) else { return nil }
        self = match
    }
}

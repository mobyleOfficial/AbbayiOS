//
//  CellularDownloadPolicy.swift
//  Abbay
//

import Foundation

enum CellularDownloadPolicy {
    /// Books above this many bytes (99 MB, summed across chapters) warn before using a metered
    /// network (cellular, Personal Hotspot, Low Data Mode).
    static let largeDownloadThreshold: Int64 = 99_000_000

    enum Decision: Equatable {
        /// `allowsCellular: false` also keeps the book off Personal Hotspot and Low Data Mode.
        case proceed(allowsCellular: Bool)
        case askUser
    }

    /// Small books count as "Continue" chosen. Large books follow the Settings preference: `.ask`
    /// asks on a metered network and on unmetered Wi-Fi proceeds without cellular, so moving to a
    /// metered network later holds the download; `.always` and `.wifiOnly` answer without asking.
    static func decide(
        totalBytes: Int64,
        isMetered: Bool,
        preference: CellularDownloadPreference = .ask
    ) -> Decision {
        if totalBytes <= largeDownloadThreshold {
            return .proceed(allowsCellular: true)
        }
        switch preference {
        case .always: return .proceed(allowsCellular: true)
        case .wifiOnly: return .proceed(allowsCellular: false)
        case .ask: break
        }
        return isMetered ? .askUser : .proceed(allowsCellular: false)
    }
}

//
//  CellularDownloadPolicy.swift
//  Abbay
//

import Foundation

enum CellularDownloadPolicy {
    /// Books above this many bytes (99 MB, summed across chapters) warn before using cellular.
    static let largeDownloadThreshold: Int64 = 99_000_000

    enum Decision: Equatable {
        case proceed(allowsCellular: Bool)
        case askUser
    }

    /// Small books count as "Continue" chosen. Large books ask on cellular; on Wi-Fi they proceed
    /// without cellular so moving to cellular later pauses the download.
    static func decide(totalBytes: Int64, isCellular: Bool) -> Decision {
        if totalBytes <= largeDownloadThreshold {
            return .proceed(allowsCellular: true)
        }
        return isCellular ? .askUser : .proceed(allowsCellular: false)
    }
}

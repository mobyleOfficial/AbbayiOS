//
//  NetworkHold+Display.swift
//  Abbay
//

import Foundation

/// How the download screens explain a hold: the chapter list's hint under the progress bar and
/// the Library row's ring.
extension NetworkHold {
    var message: String {
        switch self {
        case .cellular: Localizable.cellularHoldWaiting.localized
        case .personalHotspot: Localizable.hotspotHoldWaiting.localized
        case .lowDataMode: Localizable.lowDataModeWaiting.localized
        }
    }

    var systemImage: String {
        switch self {
        case .cellular: "antenna.radiowaves.left.and.right"
        case .personalHotspot: "personalhotspot"
        case .lowDataMode: "wifi.exclamationmark"
        }
    }

    /// The hint's identifier on the LibriVox page.
    var detailIdentifier: String {
        switch self {
        case .cellular: AccessibilityID.Detail.cellularHold
        case .personalHotspot: AccessibilityID.Detail.hotspotHold
        case .lowDataMode: AccessibilityID.Detail.lowDataMode
        }
    }

    /// The hint's identifier on the details screen.
    var playerIdentifier: String {
        switch self {
        case .cellular: AccessibilityID.Player.downloadCellularHold
        case .personalHotspot: AccessibilityID.Player.downloadHotspotHold
        case .lowDataMode: AccessibilityID.Player.downloadLowDataMode
        }
    }
}

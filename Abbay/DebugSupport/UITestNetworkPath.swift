//
//  UITestNetworkPath.swift
//  Abbay
//

#if DEBUG
import Combine
import Foundation

/// A network path that never changes, so a UI test can put the app on cellular, a Personal Hotspot
/// or Low Data Mode Wi-Fi, which a simulator can't be, or offline. Enabled by
/// `LaunchArgument.stubPathCellular`, `stubPathHotspot`, `stubPathLowDataMode` and `stubPathOffline`.
final class UITestNetworkPath: NetworkPathProviding {
    let snapshot: NetworkPathSnapshot

    init(_ snapshot: NetworkPathSnapshot) {
        self.snapshot = snapshot
    }

    static let cellular = NetworkPathSnapshot(
        isSatisfied: true, usesCellular: true, usesWiFi: false, isExpensive: true, isConstrained: false
    )
    static let hotspot = NetworkPathSnapshot(
        isSatisfied: true, usesCellular: false, usesWiFi: true, isExpensive: true, isConstrained: false
    )
    static let lowDataMode = NetworkPathSnapshot(
        isSatisfied: true, usesCellular: false, usesWiFi: true, isExpensive: false, isConstrained: true
    )

    static let offline = NetworkPathSnapshot(
        isSatisfied: false, usesCellular: false, usesWiFi: false, isExpensive: false, isConstrained: false
    )

    var isMetered: Bool { snapshot.isMetered }
    var isOnline: Bool { snapshot.isSatisfied }

    var onlinePublisher: AnyPublisher<Bool, Never> {
        Just(snapshot.isSatisfied).eraseToAnyPublisher()
    }

    var holdPublisher: AnyPublisher<NetworkHold?, Never> {
        Just(snapshot.hold).eraseToAnyPublisher()
    }
}
#endif

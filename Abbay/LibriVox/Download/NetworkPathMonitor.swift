//
//  NetworkPathMonitor.swift
//  Abbay
//

import Combine
import Foundation
import Network

protocol NetworkPathProviding: AnyObject {
    /// Cellular, Personal Hotspot or Low Data Mode: a path where a large download costs the user.
    var isMetered: Bool { get }
    var isOnline: Bool { get }
    /// `isOnline` now and on every path update. May emit on any thread.
    var onlinePublisher: AnyPublisher<Bool, Never> { get }
    /// `NetworkPathSnapshot.hold` now and on every path update. May emit on any thread.
    var holdPublisher: AnyPublisher<NetworkHold?, Never> { get }
}

/// Why the current path holds a Wait-for-Wi-Fi book (`allowsCellularDownload` false), whose tasks
/// are kept off cellular, expensive and constrained networks. The download screens say which (#171).
enum NetworkHold: Equatable, CaseIterable {
    /// On cellular data alone.
    case cellular
    /// On Wi-Fi that is expensive: a Personal Hotspot, paid for by another phone's plan.
    case personalHotspot
    /// On Wi-Fi in Low Data Mode (#148).
    case lowDataMode
}

/// The parts of an `NWPath` the app reads, so the rules can be tested without a real path.
struct NetworkPathSnapshot: Equatable {
    /// Before the first update arrives: online and not metered.
    static let unknown = NetworkPathSnapshot(
        isSatisfied: true,
        usesCellular: false,
        usesWiFi: false,
        isExpensive: false,
        isConstrained: false
    )

    let isSatisfied: Bool
    let usesCellular: Bool
    let usesWiFi: Bool
    /// True on cellular and on Personal Hotspot, which is Wi-Fi paid for by another phone's plan.
    let isExpensive: Bool
    /// True in Low Data Mode.
    let isConstrained: Bool

    var isMetered: Bool {
        isExpensive || isConstrained || (usesCellular && !usesWiFi)
    }

    /// What holds a Wait-for-Wi-Fi book here; nil offline (where nothing downloads at all) and on
    /// unmetered Wi-Fi. Cellular wins over the rest, then a hotspot, then Low Data Mode: joining
    /// a Wi-Fi network is what the user can do first.
    var hold: NetworkHold? {
        guard isSatisfied else { return nil }
        if usesCellular && !usesWiFi { return .cellular }
        if isExpensive { return .personalHotspot }
        if isConstrained { return .lowDataMode }
        return nil
    }

    /// Online over Wi-Fi that is in Low Data Mode, and nothing else metered (#148).
    var isLowDataModeWiFi: Bool {
        hold == .lowDataMode
    }
}

extension NetworkPathSnapshot {
    init(_ path: NWPath) {
        self.init(
            isSatisfied: path.status == .satisfied,
            usesCellular: path.usesInterfaceType(.cellular),
            usesWiFi: path.usesInterfaceType(.wifi),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }
}

/// Exposes the current network path synchronously. Before the first update arrives it reports
/// online and not metered.
final class NetworkPathMonitor: NetworkPathProviding {
    static let shared = NetworkPathMonitor()
    /// The path the download screens read: `shared`, or a fixed one a UI test asked for
    /// (`DebugOverrides.networkPath`).
    static let app: NetworkPathProviding = DebugOverrides.networkPath() ?? shared

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.edyuto.Abbay.networkPathMonitor")
    private let lock = NSLock()
    private var latestPath = NetworkPathSnapshot.unknown
    private let onlineSubject = CurrentValueSubject<Bool, Never>(NetworkPathSnapshot.unknown.isSatisfied)
    private let holdSubject = CurrentValueSubject<NetworkHold?, Never>(NetworkPathSnapshot.unknown.hold)

    var isMetered: Bool {
        currentPath.isMetered
    }

    var isOnline: Bool {
        currentPath.isSatisfied
    }

    var onlinePublisher: AnyPublisher<Bool, Never> {
        onlineSubject.eraseToAnyPublisher()
    }

    var holdPublisher: AnyPublisher<NetworkHold?, Never> {
        holdSubject.eraseToAnyPublisher()
    }

    private var currentPath: NetworkPathSnapshot {
        lock.withLock { latestPath }
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let snapshot = NetworkPathSnapshot(path)
            lock.withLock { self.latestPath = snapshot }
            onlineSubject.send(snapshot.isSatisfied)
            holdSubject.send(snapshot.hold)
        }
        monitor.start(queue: queue)
    }
}

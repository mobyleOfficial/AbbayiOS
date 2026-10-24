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

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.edyuto.Abbay.networkPathMonitor")
    private let lock = NSLock()
    private var latestPath = NetworkPathSnapshot.unknown
    private let onlineSubject = CurrentValueSubject<Bool, Never>(NetworkPathSnapshot.unknown.isSatisfied)

    var isMetered: Bool {
        currentPath.isMetered
    }

    var isOnline: Bool {
        currentPath.isSatisfied
    }

    var onlinePublisher: AnyPublisher<Bool, Never> {
        onlineSubject.eraseToAnyPublisher()
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
        }
        monitor.start(queue: queue)
    }
}

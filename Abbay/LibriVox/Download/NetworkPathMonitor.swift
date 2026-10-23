//
//  NetworkPathMonitor.swift
//  Abbay
//

import Foundation
import Network

protocol NetworkPathProviding: AnyObject {
    var isCellular: Bool { get }
    var isOnline: Bool { get }
}

/// Exposes the current network path synchronously. Before the first update arrives it reports
/// online and not cellular.
final class NetworkPathMonitor: NetworkPathProviding {
    static let shared = NetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.edyuto.Abbay.networkPathMonitor")
    private let lock = NSLock()
    private var latestPath: NWPath?

    var isCellular: Bool {
        guard let path = currentPath else { return false }
        return path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
    }

    var isOnline: Bool {
        guard let path = currentPath else { return true }
        return path.status == .satisfied
    }

    private var currentPath: NWPath? {
        lock.lock()
        defer { lock.unlock() }
        return latestPath
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.latestPath = path
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}

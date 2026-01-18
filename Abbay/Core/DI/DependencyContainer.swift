//
//  DependencyContainer.swift
//  Abbay
//

import Foundation

protocol DependencyContainerProtocol {
    var player: PlayerProtocol { get }
}

final class DependencyContainer: DependencyContainerProtocol {
    private static var _shared: DependencyContainerProtocol?

    static var shared: DependencyContainerProtocol {
        guard let container = _shared else {
            fatalError("DependencyContainer not configured. Call configure() in AppDelegate.")
        }
        return container
    }

    static func configure(with container: DependencyContainerProtocol? = nil) {
        _shared = container ?? DependencyContainer()
    }

    static func reset() {
        _shared = nil
    }

    let player: PlayerProtocol

    private init() {
        self.player = Player()
    }
}

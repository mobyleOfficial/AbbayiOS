//
//  ConstantsProtocol.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import Foundation

protocol ConstantsProtocol {
    associatedtype Value

    var value: Value { get }
    var rawValue: String { get }
    var resource: String { get }
    var resourceExtensions: String { get }

    func getBaseValue<T>() -> T
}

// MARK: - Default implementations
extension ConstantsProtocol {
    var resource: String {
        String(describing: Self.self)
    }

    var resourceExtensions: String {
        "plist"
    }

    func getBaseValue<T>() -> T {
        guard let storage = getStorage() as? [String: T],
              let value = storage[self.rawValue]
        else {
            fatalError("Could not load value for \(resource)")
        }
        return value
    }

    var value: Value {
        getBaseValue()
    }
}

// MARK: - Storage
extension ConstantsProtocol {
    private func getStorage() -> Any? {
        if let storage = LocalStorage.data[resource] {
            return storage
        }
        if let url = AbbayBundle.resources.url(
            forResource: resource,
            withExtension: resourceExtensions
        ),
           let data = try? Data(contentsOf: url),
           let storage = try? PropertyListSerialization.propertyList(
            from: data, format: nil
           ) {
            LocalStorage.data[resource] = storage
            return storage
        }
        return nil
    }
}

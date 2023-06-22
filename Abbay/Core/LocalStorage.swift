//
//  LocalStorage.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 22/06/23.
//

import Foundation

final class LocalStorage {
    static let data = LocalStorage()

    private var storage = [String: Any]()

    private init() {}

    func getValue(forKey key: String) -> Any? {
        storage[key]
    }

    func put(_ value: Any, withKey key: String) {
        self.storage[key] = value
    }
}

extension LocalStorage {
    subscript(key: String) -> Any? {
        get {
            getValue(forKey: key)
        }
        set {
            if let value = newValue {
                put(value, withKey: key)
            }
        }
    }
}

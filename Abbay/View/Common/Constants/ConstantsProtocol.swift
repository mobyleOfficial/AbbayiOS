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
}

extension ConstantsProtocol {
    var resource: String {
        String(describing: Self.self)
    }

    var resourceExtensions: String {
        "plist"
    }

    func getBaseValue<T>() -> T {
        guard let url = Bundle.main.url(
            forResource: resource,
            withExtension: resourceExtensions
        ),
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(
                from: data, format: nil
              )  as? [String: T],
              let value = propertyList[self.rawValue]
        else {
            fatalError("Could not load value for \(resource)")
        }
        return value
    }

    var value: Value {
        getBaseValue()
    }
}

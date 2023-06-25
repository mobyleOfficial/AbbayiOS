//
//  LocalStorage.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 22/06/23.
//

import Foundation

final class LocalStorage {
    static let data = Cache<String, Any>()

    private init() {}
}

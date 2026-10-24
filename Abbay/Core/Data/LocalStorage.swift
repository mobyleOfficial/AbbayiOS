//
//  LocalStorage.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 22/06/23.
//

import Foundation

final class LocalStorage {
    static let data = Cache<String, Any>()
    static let persistent = DataStack(modelName: "AudioDataModel")
    /// App preferences (`AppSettings`). The app's own defaults, not the App Group: the Siri
    /// extension reads none of them.
    static let preferences: KeyValueStoring = UserDefaults.standard

    private init() {}
}

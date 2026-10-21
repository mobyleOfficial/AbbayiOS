//
//  Dictionary+extensions.swift
//  NetworkProviderTests
//
//  Created on 21/10/26.
//

import Foundation

extension Dictionary {
    func toNSDictionary() -> NSDictionary {
        return NSDictionary(dictionary: self)
    }
}

//
//  NetworkErrors+extensions.swift
//  NetworkProviderTests
//
//  Created on 21/10/26.
//

import Foundation
import NetworkProvider

extension NetworkError {
    init?(error: NSError) {
        guard error.domain == "NetworkProviderTests.NetworkError" else { return nil }
        switch error.code {
        case 0:
            self = .connection
        case 1:
            self = .decoding(description: String(), statusCode: -1)
        case 2:
            self = .invalidParams
        case 3:
            self = .invalidResponse
        case 4:
            self = .invalidUrl
        default:
            return nil
        }
    }
}

//
//  URLSessionDataLoading.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// The one network call `NetworkProvider` awaits. Internal so it stays an implementation detail.
protocol URLSessionDataLoading {
    func load(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataLoading {
    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

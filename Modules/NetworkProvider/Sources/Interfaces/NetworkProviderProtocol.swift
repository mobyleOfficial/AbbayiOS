//
//  NetworkProviderProtocol.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// Performs network requests.
public protocol NetworkProviderProtocol {
    /// Performs the request and decodes the body with the request's decoder.
    func makeRequest<T: Decodable>(_ request: NetworkRequestProtocol) async throws -> NetworkResponse<T>
    /// Performs the request and returns the raw body.
    func makeRequest(_ request: NetworkRequestProtocol) async throws -> NetworkResponse<Data>
}

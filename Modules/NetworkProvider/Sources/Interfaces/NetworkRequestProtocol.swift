//
//  NetworkRequestProtocol.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// Describes a single network request.
public protocol NetworkRequestProtocol {
    /// URL string, optionally containing path-parameter placeholders.
    var endpoint: String { get }
    /// Values substituted into the endpoint's placeholders.
    var pathParams: [String: String]? { get }
    /// HTTP body.
    var body: Data? { get }
    /// HTTP method.
    var httpMethod: HTTPMethod { get }
    /// Query items appended to the URL.
    var queryParams: [String: String]? { get }
    /// HTTP header fields.
    var headers: [String: String]? { get }
    /// Cache policy of the URL request.
    var cachePolicy: URLRequest.CachePolicy { get }
    /// Decoder used for typed responses.
    var decoder: JSONDecoder { get }
}

public extension NetworkRequestProtocol {
    /// Defaults to the protocol cache policy.
    var cachePolicy: URLRequest.CachePolicy { .useProtocolCachePolicy }
    /// Defaults to no path parameters.
    var pathParams: [String: String]? { nil }
}

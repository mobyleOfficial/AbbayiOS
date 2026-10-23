//
//  NetworkRequest.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

public struct NetworkRequest: NetworkRequestProtocol {
    public var endpoint: String
    public var pathParams: [String: String]?
    public var body: Data?
    public var httpMethod: HTTPMethod
    public var queryParams: [String: String]?
    public var headers: [String: String]?
    public var cachePolicy: URLRequest.CachePolicy
    public var timeoutInterval: TimeInterval?
    public var decoder: JSONDecoder

    public init(
        endpoint: String,
        pathParams: [String: String]? = nil,
        body: Data? = nil,
        httpMethod: HTTPMethod = .get,
        queryParams: [String: String]? = nil,
        headers: [String: String]? = nil,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        timeoutInterval: TimeInterval? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.endpoint = endpoint
        self.pathParams = pathParams
        self.body = body
        self.httpMethod = httpMethod
        self.queryParams = queryParams
        self.headers = headers
        self.cachePolicy = cachePolicy
        self.timeoutInterval = timeoutInterval
        self.decoder = decoder
    }
}

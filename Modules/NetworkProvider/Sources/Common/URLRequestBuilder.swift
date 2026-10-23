//
//  URLRequestBuilder.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// Turns a `NetworkRequestProtocol` into a `URLRequest`. Shared by data requests and downloads.
enum URLRequestBuilder {
    static func build(from request: NetworkRequestProtocol) throws -> URLRequest {
        let endpoint = try PathTemplate.resolve(request.endpoint, with: request.pathParams)
        guard var urlComponents = URLComponents(string: endpoint) else {
            throw NetworkError.invalidUrl
        }
        urlComponents.queryItems = request.queryParams?.compactMap { key, value in
            URLQueryItem(name: key, value: value)
        }

        guard let url = urlComponents.url else {
            throw NetworkError.invalidParams
        }

        var urlRequest = URLRequest(url: url, cachePolicy: request.cachePolicy)
        if let timeout = request.timeoutInterval {
            urlRequest.timeoutInterval = timeout
        }
        urlRequest.httpMethod = request.httpMethod.rawValue
        urlRequest.httpBody = request.body
        request.headers?.forEach { key, value in
            urlRequest.addValue(value, forHTTPHeaderField: key)
        }

        return urlRequest
    }
}

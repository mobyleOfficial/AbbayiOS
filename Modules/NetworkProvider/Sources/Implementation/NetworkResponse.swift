//
//  NetworkResponse.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

/// The status code, headers and decoded (or raw) content of a completed request.
public struct NetworkResponse<T> {
    /// HTTP status code.
    public let statusCode: Int
    /// HTTP response headers.
    public let headers: [AnyHashable: Any]
    /// Response payload.
    public let content: T

    /// Creates a response value.
    public init(statusCode: Int, headers: [AnyHashable: Any], content: T) {
        self.statusCode = statusCode
        self.headers = headers
        self.content = content
    }
}

//
//  NetworkErrors.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

public enum NetworkError: Error, Equatable {
    case cancelledRequest
    case connection
    case decoding(description: String, statusCode: Int)
    /// A downloaded file could not be moved out of URLSession's temporary area.
    case fileSystem
    /// The server answered a download with a non-2xx status code.
    case httpStatus(Int)
    case invalidParams
    case invalidResponse
    case invalidUrl
    case missingPathParam(name: String)
    case unusedPathParam(name: String)
}

enum ConnectionError: Int {
    case timeout = -1001
    case cannotConnectToHost = -1004
    case connectionLost = -1005
    case unreachable = -1009
}

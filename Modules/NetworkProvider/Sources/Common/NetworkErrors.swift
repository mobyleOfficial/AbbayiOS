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

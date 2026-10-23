//
//  MockNetworkProvider.swift
//  AbbayTests
//

import Foundation
import NetworkProvider

/// Records every request and answers it from a handler, so tests choose a fixture per endpoint and query.
final class MockNetworkProvider: NetworkProviderProtocol {
    struct Reply {
        var statusCode = 200
        var data: Data
    }

    private let lock = NSLock()
    private var recorded = [NetworkRequestProtocol]()
    var handler: (NetworkRequestProtocol) throws -> Reply

    init(handler: @escaping (NetworkRequestProtocol) throws -> Reply = { _ in Reply(data: Data()) }) {
        self.handler = handler
    }

    var requests: [NetworkRequestProtocol] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func makeRequest<T: Decodable>(_ request: NetworkRequestProtocol) async throws -> NetworkResponse<T> {
        let reply = try reply(to: request)
        do {
            let content = try request.decoder.decode(T.self, from: reply.data)
            return NetworkResponse(statusCode: reply.statusCode, headers: [:], content: content)
        } catch {
            // Same shape as the real provider: the body is decoded whatever the status.
            throw NetworkError.decoding(description: error.localizedDescription, statusCode: reply.statusCode)
        }
    }

    func makeRequest(_ request: NetworkRequestProtocol) async throws -> NetworkResponse<Data> {
        let reply = try reply(to: request)
        return NetworkResponse(statusCode: reply.statusCode, headers: [:], content: reply.data)
    }

    private func reply(to request: NetworkRequestProtocol) throws -> Reply {
        lock.lock()
        recorded.append(request)
        lock.unlock()
        return try handler(request)
    }
}

//
//  URLProtocolMock.swift
//  NetworkProviderTests
//
//  Created on 21/10/26.
//

import Foundation
import NetworkProvider

final class URLProtocolMock: URLProtocol {
    private static let semaphore = DispatchSemaphore(value: 1)
    static var data: Data?
    static var response: HTTPURLResponse?
    static var error: Error?
    static var request: URLRequest?
    /// Seconds to wait before answering. Lets tests cancel a request while it's in flight.
    static var delay: TimeInterval = 0

    private var isStopped = false

    static func setup() {
        semaphore.wait()
    }

    static func tearDown() {
        data = nil
        response = nil
        error = nil
        request = nil
        delay = 0
        semaphore.signal()
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        Self.request = request
        return request
    }

    override func startLoading() {
        guard Self.delay > 0 else {
            deliver()
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [weak self] in
            self?.deliver()
        }
    }

    override func stopLoading() {
        isStopped = true
    }

    private func deliver() {
        guard !isStopped else { return }

        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        guard let response = Self.response else {
            client?.urlProtocol(self, didFailWithError: NetworkError.invalidResponse)
            return
        }

        if let data = Self.data {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}

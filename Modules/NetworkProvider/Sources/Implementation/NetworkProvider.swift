//
//  NetworkProvider.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// URLSession-backed implementation of `NetworkProviderProtocol`.
public final class NetworkProvider {
    private let loader: URLSessionDataLoading

    /// Creates a provider that performs requests on the given session.
    public init(session: URLSession = .shared) {
        self.loader = session
    }

    /// Test seam: lets tests control the single suspension point of a request.
    init(loader: URLSessionDataLoading) {
        self.loader = loader
    }

    private func buildRequest(with request: NetworkRequestProtocol) throws -> URLRequest {
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
        urlRequest.httpMethod = request.httpMethod.rawValue
        urlRequest.httpBody = request.body
        request.headers?.forEach { key, value in
            urlRequest.addValue(value, forHTTPHeaderField: key)
        }

        return urlRequest
    }
}

// MARK: - NetworkProviderProtocol
extension NetworkProvider: NetworkProviderProtocol {
    public func makeRequest<T: Decodable>(_ request: NetworkRequestProtocol) async throws -> NetworkResponse<T> {
        let response = try await makeRequest(request)
        try checkCancellation()
        do {
            let content = try request.decoder.decode(T.self, from: response.content)
            return NetworkResponse(
                statusCode: response.statusCode,
                headers: response.headers,
                content: content
            )
        } catch {
            throw NetworkError.decoding(description: error.localizedDescription, statusCode: response.statusCode)
        }
    }

    public func makeRequest(_ request: NetworkRequestProtocol) async throws -> NetworkResponse<Data> {
        try checkCancellation()
        let urlRequest = try buildRequest(with: request)

        do {
            let (data, response) = try await loader.load(urlRequest)
            try checkCancellation()

            guard let response = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            return NetworkResponse(
                statusCode: response.statusCode,
                headers: response.allHeaderFields,
                content: data
            )
        } catch let error as NetworkError {
            throw error
        } catch is CancellationError {
            throw NetworkError.cancelledRequest
        } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            throw NetworkError.cancelledRequest
        } catch let error as NSError where ConnectionError(rawValue: error.code) != nil {
            throw NetworkError.connection
        } catch {
            throw error
        }
    }
}

// MARK: - Cancellation
private extension NetworkProvider {
    /// Swift tasks are cancelled cooperatively; check before starting and after every suspension point.
    func checkCancellation() throws {
        if Task.isCancelled {
            throw NetworkError.cancelledRequest
        }
    }
}

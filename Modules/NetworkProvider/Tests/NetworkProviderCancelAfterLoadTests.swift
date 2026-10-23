//
//  NetworkProviderCancelAfterLoadTests.swift
//  NetworkProviderTests
//
//  Created on 21/10/26.
//

@testable import NetworkProvider
import XCTest

/// URLSession gives no deterministic hook between `data(for:)` returning and decoding,
/// so these tests drive `NetworkProvider` through a loader that cancels its own task
/// and then returns a successful response.
final class NetworkProviderCancelAfterLoadTests: XCTestCase {
    func testCancelledAfterDataArrivesThrowsCancelledRequestNotDecoding() async {
        let sut = NetworkProvider(loader: CancellingLoader(payload: Data("not json".utf8)))
        let task = Task { () -> Error? in
            do {
                let _: NetworkResponse<Payload> = try await sut.makeRequest(
                    NetworkRequest(endpoint: "https://api.test/x")
                )
                return nil
            } catch {
                return error
            }
        }

        let error = await task.value

        guard case .cancelledRequest = error as? NetworkError else {
            XCTFail("Expected NetworkError.cancelledRequest, got \(String(describing: error))")
            return
        }
    }

    func testDataRequestCancelledAfterDataArrivesThrowsCancelledRequest() async {
        let sut = NetworkProvider(loader: CancellingLoader(payload: Data()))
        let task = Task { () -> Error? in
            do {
                _ = try await sut.makeRequest(NetworkRequest(endpoint: "https://api.test/x"))
                return nil
            } catch {
                return error
            }
        }

        let error = await task.value

        guard case .cancelledRequest = error as? NetworkError else {
            XCTFail("Expected NetworkError.cancelledRequest, got \(String(describing: error))")
            return
        }
    }
}

/// Succeeds, but cancels the calling task first, as if cancellation raced the response.
private struct CancellingLoader: URLSessionDataLoading {
    let payload: Data

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        withUnsafeCurrentTask { $0?.cancel() }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (payload, response)
    }
}

private struct Payload: Decodable {
    let value: String
}

//
//  NetworkProviderCancellationTests.swift
//  NetworkProviderTests
//
//  Created on 21/10/26.
//

import NetworkProvider
import XCTest

final class NetworkProviderCancellationTests: XCTestCase {
    private var sut: NetworkProvider!

    override func setUp() {
        super.setUp()
        URLProtocolMock.setup()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        sut = NetworkProvider(session: URLSession(configuration: configuration))
        URLProtocolMock.data = Data("not json".utf8)
        URLProtocolMock.response = HTTPURLResponse(
            url: URL(string: #file)!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    override func tearDown() {
        URLProtocolMock.tearDown()
        sut = nil
        super.tearDown()
    }

    func testCancelledBeforeStartThrowsCancelledRequestWithoutHittingNetwork() async {
        let sut = self.sut!
        let task = Task { () -> Error? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await sut.makeRequest(NetworkRequest(endpoint: #file))
                return nil
            } catch {
                return error
            }
        }

        let error = await task.value

        assertCancelledRequest(error)
        XCTAssertNil(URLProtocolMock.request, "A cancelled task must not reach the network")
    }

    func testDecodingRequestCancelledBeforeStartThrowsCancelledRequestNotDecoding() async {
        let sut = self.sut!
        let task = Task { () -> Error? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                let _: NetworkResponse<Payload> = try await sut.makeRequest(NetworkRequest(endpoint: #file))
                return nil
            } catch {
                return error
            }
        }

        assertCancelledRequest(await task.value)
    }

    func testCancelledInFlightThrowsCancelledRequest() async throws {
        URLProtocolMock.delay = 1
        let sut = self.sut!
        let task = Task { () -> Error? in
            do {
                let _: NetworkResponse<Payload> = try await sut.makeRequest(NetworkRequest(endpoint: #file))
                return nil
            } catch {
                return error
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        assertCancelledRequest(await task.value)
    }

    private func assertCancelledRequest(_ error: Error?, file: StaticString = #filePath, line: UInt = #line) {
        guard case .cancelledRequest = error as? NetworkError else {
            XCTFail("Expected NetworkError.cancelledRequest, got \(String(describing: error))", file: file, line: line)
            return
        }
    }
}

private struct Payload: Decodable {
    let value: String
}

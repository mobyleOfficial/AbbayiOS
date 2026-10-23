//
//  NetworkProviderPathParamsTests.swift
//  NetworkProviderTests
//
//  Created on 21/10/26.
//

import NetworkProvider
import XCTest

final class NetworkProviderPathParamsTests: XCTestCase {
    private var sut: NetworkProvider!

    override func setUp() {
        super.setUp()
        URLProtocolMock.setup()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        sut = NetworkProvider(session: URLSession(configuration: configuration))
        URLProtocolMock.data = Data()
        URLProtocolMock.response = HTTPURLResponse(
            url: URL(string: "https://api.test")!,
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

    func testSubstitutesSingleParam() async throws {
        _ = try await sut.makeRequest(NetworkRequest(
            endpoint: "https://api.test/restaurants/{uuid}/meals",
            pathParams: ["uuid": "abc-123"]
        ))
        XCTAssertEqual(URLProtocolMock.request?.url?.absoluteString, "https://api.test/restaurants/abc-123/meals")
    }

    func testSubstitutesSeveralParamsAndKeepsQuery() async throws {
        _ = try await sut.makeRequest(NetworkRequest(
            endpoint: "https://api.test/a/{first}/b/{second_id}",
            pathParams: ["first": "1", "second_id": "2"],
            queryParams: ["page": "0"]
        ))
        XCTAssertEqual(URLProtocolMock.request?.url?.absoluteString, "https://api.test/a/1/b/2?page=0")
    }

    func testRepeatedPlaceholderIsSubstitutedEverywhere() async throws {
        _ = try await sut.makeRequest(NetworkRequest(
            endpoint: "https://api.test/{id}/copy/{id}",
            pathParams: ["id": "7"]
        ))
        XCTAssertEqual(URLProtocolMock.request?.url?.absoluteString, "https://api.test/7/copy/7")
    }

    func testEncodesReservedCharactersAsOneSegment() async throws {
        _ = try await sut.makeRequest(NetworkRequest(
            endpoint: "https://api.test/coupons/{code}",
            pathParams: ["code": "a/b?c d#e"]
        ))
        XCTAssertEqual(URLProtocolMock.request?.url?.absoluteString, "https://api.test/coupons/a%2Fb%3Fc%20d%23e")
    }

    func testEndpointWithoutPlaceholdersIsUnchanged() async throws {
        _ = try await sut.makeRequest(NetworkRequest(endpoint: "https://api.test/orders"))
        XCTAssertEqual(URLProtocolMock.request?.url?.absoluteString, "https://api.test/orders")
    }

    func testMissingParamThrows() async {
        await assertThrows(
            NetworkRequest(endpoint: "https://api.test/restaurants/{uuid}", pathParams: [:])
        ) { error in
            guard case .missingPathParam(let name) = error else { return false }
            return name == "uuid"
        }
    }

    func testUnusedParamThrows() async {
        await assertThrows(
            NetworkRequest(endpoint: "https://api.test/restaurants", pathParams: ["uuid": "1"])
        ) { error in
            guard case .unusedPathParam(let name) = error else { return false }
            return name == "uuid"
        }
    }

    func testEmptyPathParamValueThrowsInvalidParams() async {
        await assertThrows(
            NetworkRequest(endpoint: "https://api.test/restaurants/{uuid}/meals", pathParams: ["uuid": ""])
        ) { error in
            guard case .invalidParams = error else { return false }
            return true
        }
    }

    private func assertThrows(
        _ request: NetworkRequest,
        file: StaticString = #filePath,
        line: UInt = #line,
        matching predicate: (NetworkError) -> Bool
    ) async {
        do {
            _ = try await sut.makeRequest(request)
            XCTFail("Expected an error", file: file, line: line)
        } catch let error as NetworkError {
            XCTAssertTrue(predicate(error), "Unexpected error \(error)", file: file, line: line)
            XCTAssertNil(URLProtocolMock.request, "Invalid requests must not reach the network", file: file, line: line)
        } catch {
            XCTFail("Expected NetworkError, got \(error)", file: file, line: line)
        }
    }
}

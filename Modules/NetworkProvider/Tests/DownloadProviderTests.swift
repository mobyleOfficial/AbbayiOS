//
//  DownloadProviderTests.swift
//  NetworkProviderTests
//
//  Created on 21/10/26.
//

import NetworkProvider
import XCTest

final class DownloadProviderTests: XCTestCase {
    private var sut: DownloadProvider!
    private var recorder: EventRecorder!
    private var resumeDataDirectory: URL!

    override func setUp() {
        super.setUp()
        URLProtocolMock.setup()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        resumeDataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadProviderTests-\(UUID().uuidString)")
        sut = DownloadProvider(kind: .foreground(configuration), resumeDataDirectory: resumeDataDirectory)
        recorder = EventRecorder(events: sut.events)
        URLProtocolMock.response = response(statusCode: 200)
    }

    override func tearDown() async throws {
        // Stop anything still in flight before the next test reuses the mock's static stubs.
        let running = await sut.runningIDs()
        let stopped = running.map { id in
            recorder.expectation(description: "\(id) stopped") { $0 == .failed(id: id, error: .cancelledRequest) }
        }
        running.forEach { sut.cancel(id: $0) }
        await fulfillment(of: stopped, timeout: 5)

        recorder.stop()
        try? FileManager.default.removeItem(at: resumeDataDirectory)
        sut = nil
        recorder = nil
        URLProtocolMock.tearDown()
        try await super.tearDown()
    }

    func test_start_emitsFinished_withFileContainingBody() async throws {
        URLProtocolMock.data = Data([1, 2, 3])

        try sut.start(NetworkRequest(endpoint: "https://example.com/a.mp3"), id: "a", allowsCellularAccess: true)

        let location = try await awaitFinished(id: "a")
        XCTAssertEqual(try Data(contentsOf: location), Data([1, 2, 3]))
        try? FileManager.default.removeItem(at: location)
    }

    func test_start_buildsRequestFromNetworkRequest() async throws {
        let request = NetworkRequest(
            endpoint: "https://example.com/books/{id}",
            pathParams: ["id": "200"],
            queryParams: ["format": "mp3"]
        )

        for allowsCellularAccess in [true, false] {
            let id = "cellular-\(allowsCellularAccess)"
            try sut.start(request, id: id, allowsCellularAccess: allowsCellularAccess)
            let location = try await awaitFinished(id: id)
            try? FileManager.default.removeItem(at: location)

            XCTAssertEqual(URLProtocolMock.request?.url?.absoluteString, "https://example.com/books/200?format=mp3")
            XCTAssertEqual(URLProtocolMock.request?.allowsCellularAccess, allowsCellularAccess)
        }
    }

    /// Cellular off also holds the download on Personal Hotspot (expensive) and Low Data Mode
    /// (constrained), which `allowsCellularAccess` alone doesn't.
    func test_start_withoutCellular_alsoDisallowsExpensiveAndConstrainedNetworks() async throws {
        let request = NetworkRequest(endpoint: "https://example.com/a.mp3")

        for allowsCellularAccess in [true, false] {
            let id = "metered-\(allowsCellularAccess)"
            try sut.start(request, id: id, allowsCellularAccess: allowsCellularAccess)
            let location = try await awaitFinished(id: id)
            try? FileManager.default.removeItem(at: location)

            XCTAssertEqual(URLProtocolMock.request?.allowsExpensiveNetworkAccess, allowsCellularAccess)
            XCTAssertEqual(URLProtocolMock.request?.allowsConstrainedNetworkAccess, allowsCellularAccess)
        }
    }

    func test_start_non2xx_emitsFailedHttpStatus() async throws {
        URLProtocolMock.response = response(statusCode: 404)

        try sut.start(NetworkRequest(endpoint: "https://example.com/a.mp3"), id: "a", allowsCellularAccess: true)

        await awaitEvent(.failed(id: "a", error: .httpStatus(404)))
    }

    func test_start_connectionError_emitsFailedConnection() async throws {
        URLProtocolMock.error = URLError(.notConnectedToInternet)

        try sut.start(NetworkRequest(endpoint: "https://example.com/a.mp3"), id: "a", allowsCellularAccess: true)

        await awaitEvent(.failed(id: "a", error: .connection))
    }

    func test_cancel_emitsCancelledAndRemovesResumeData() async throws {
        URLProtocolMock.delay = 1
        try sut.start(NetworkRequest(endpoint: "https://example.com/a.mp3"), id: "a", allowsCellularAccess: true)
        // Resume data left by an earlier pause must not survive a cancel.
        try FileManager.default.createDirectory(at: resumeDataDirectory, withIntermediateDirectories: true)
        try Data([9]).write(to: resumeDataDirectory.appendingPathComponent("a.resume"))

        sut.cancel(id: "a")

        await awaitEvent(.failed(id: "a", error: .cancelledRequest))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: resumeDataDirectory.path)) ?? []
        XCTAssertFalse(files.contains { $0.hasPrefix("a") }, "Found leftover files: \(files)")
    }

    func test_runningIDs_reportsStartedTask() async throws {
        URLProtocolMock.delay = 1

        try sut.start(NetworkRequest(endpoint: "https://example.com/a.mp3"), id: "a", allowsCellularAccess: true)

        let running = await sut.runningIDs()
        XCTAssertEqual(running, ["a"])
    }

    func test_start_invalidEndpoint_throwsInvalidUrl() {
        XCTAssertThrowsError(
            try sut.start(NetworkRequest(endpoint: "ht tp://"), id: "a", allowsCellularAccess: true)
        ) { error in
            XCTAssertEqual(error as? NetworkError, .invalidUrl)
        }
    }

    func test_handleBackgroundEvents_afterSessionFinishedEvents_callsCompletionOnMain() async {
        let completed = expectation(description: "completion called")
        // The system may deliver this before the app delegate hands over its handler.
        sut.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)

        sut.handleBackgroundEvents {
            XCTAssertTrue(Thread.isMainThread)
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 5)
    }

    func test_handleBackgroundEvents_beforeSessionFinishedEvents_callsCompletionOnce() async {
        let completed = expectation(description: "completion called")
        completed.assertForOverFulfill = true
        sut.handleBackgroundEvents { completed.fulfill() }

        sut.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)
        sut.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession.shared)

        await fulfillment(of: [completed], timeout: 5)
    }

    func test_resume_withoutResumeData_throwsInvalidParams() {
        XCTAssertThrowsError(try sut.resume(id: "a", allowsCellularAccess: true)) { error in
            XCTAssertEqual(error as? NetworkError, .invalidParams)
        }
    }
}

// MARK: - Helpers
private extension DownloadProviderTests {
    func response(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    func awaitEvent(_ event: DownloadEvent) async {
        let expectation = recorder.expectation(description: "\(event)") { $0 == event }
        await fulfillment(of: [expectation], timeout: 5)
    }

    func awaitFinished(id: String, file: StaticString = #filePath, line: UInt = #line) async throws -> URL {
        let isFinished: (DownloadEvent) -> Bool = { event in
            if case .finished(id, _) = event { return true }
            return false
        }
        let expectation = recorder.expectation(description: "\(id) finished", where: isFinished)
        await fulfillment(of: [expectation], timeout: 5)
        guard case let .finished(_, location) = recorder.events.first(where: isFinished) else {
            XCTFail("Expected \(id) to finish, got \(recorder.events)", file: file, line: line)
            throw NetworkError.invalidResponse
        }
        return location
    }
}

/// Drains the provider's stream on one task for the whole test, and fulfills expectations as matching events arrive.
private final class EventRecorder {
    private let lock = NSLock()
    private var received: [DownloadEvent] = []
    private var waiters: [(matches: (DownloadEvent) -> Bool, expectation: XCTestExpectation)] = []
    private var task: Task<Void, Never>?

    var events: [DownloadEvent] {
        lock.withLock { received }
    }

    init(events: AsyncStream<DownloadEvent>) {
        task = Task { [weak self] in
            for await event in events {
                self?.record(event)
            }
        }
    }

    func expectation(description: String, where matches: @escaping (DownloadEvent) -> Bool) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: description)
        lock.withLock {
            if received.contains(where: matches) {
                expectation.fulfill()
            } else {
                waiters.append((matches, expectation))
            }
        }
        return expectation
    }

    func stop() {
        task?.cancel()
    }

    private func record(_ event: DownloadEvent) {
        lock.withLock {
            received.append(event)
            waiters.removeAll { waiter in
                guard waiter.matches(event) else { return false }
                waiter.expectation.fulfill()
                return true
            }
        }
    }
}

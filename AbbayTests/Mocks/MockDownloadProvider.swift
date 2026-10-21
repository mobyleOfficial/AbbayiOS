//
//  MockDownloadProvider.swift
//  AbbayTests
//

import Foundation
import NetworkProvider

/// Records every call and lets the test push `DownloadEvent`s. Main-thread only, like the manager.
final class MockDownloadProvider: DownloadProviderProtocol {
    struct StartCall: Equatable {
        let id: String
        let url: String
        let allowsCellularAccess: Bool
    }

    let events: AsyncStream<DownloadEvent>
    private let continuation: AsyncStream<DownloadEvent>.Continuation

    private(set) var startCalls: [StartCall] = []
    private(set) var resumeCalls: [String] = []
    private(set) var pauseCalls: [String] = []
    private(set) var cancelCalls: [String] = []
    private(set) var backgroundCompletion: (() -> Void)?
    /// Ids that have resume data; `resume` throws `.invalidParams` for any other id.
    var resumableIDs: Set<String> = []
    var running: Set<String> = []
    /// Called after every recorded call, so tests can wait on calls the manager makes asynchronously.
    var onCall: (() -> Void)?

    init() {
        (events, continuation) = AsyncStream.makeStream(of: DownloadEvent.self)
    }

    var startedIDs: [String] {
        startCalls.map(\.id)
    }

    func send(_ event: DownloadEvent) {
        continuation.yield(event)
    }

    func start(_ request: NetworkRequestProtocol, id: String, allowsCellularAccess: Bool) throws {
        startCalls.append(StartCall(id: id, url: request.endpoint, allowsCellularAccess: allowsCellularAccess))
        onCall?()
    }

    func pause(id: String) async {
        pauseCalls.append(id)
        resumableIDs.insert(id)
        onCall?()
    }

    func resume(id: String, allowsCellularAccess: Bool) throws {
        resumeCalls.append(id)
        onCall?()
        guard resumableIDs.remove(id) != nil else { throw NetworkError.invalidParams }
    }

    func cancel(id: String) {
        cancelCalls.append(id)
        resumableIDs.remove(id)
        onCall?()
    }

    func runningIDs() async -> Set<String> {
        running
    }

    func handleBackgroundEvents(completion: @escaping () -> Void) {
        backgroundCompletion = completion
        onCall?()
    }
}

//
//  DownloadProvider.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// URLSession-backed implementation of `DownloadProviderProtocol`.
///
/// Background sessions only support the delegate API, so this class is the session's delegate and
/// turns its callbacks into `DownloadEvent`s. Each task's `taskDescription` holds its download id.
public final class DownloadProvider: NSObject {
    /// Progress, completion and failure of every download.
    public let events: AsyncStream<DownloadEvent>

    private let continuation: AsyncStream<DownloadEvent>.Continuation
    private let configuration: URLSessionConfiguration
    private let resumeDataDirectory: URL
    /// Serial, so the delegate callbacks (the only code that yields events or touches `progress`) never overlap.
    private let delegateQueue: OperationQueue
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var backgroundCompletion: (() -> Void)?
    /// The last progress event emitted per id, used for throttling. Only touched on `delegateQueue`.
    private var progress: [String: ProgressMark] = [:]
    /// Lazy only because the session needs `self` as its delegate. Forced at the end of `init`.
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)

    /// Creates the provider and its session. For a background kind, this also re-attaches to the
    /// tasks the system kept running while the app was not.
    /// - Parameter resumeDataDirectory: Where paused downloads keep their resume data, one file per id.
    public init(kind: DownloadSessionKind, resumeDataDirectory: URL) {
        switch kind {
        case let .foreground(configuration):
            self.configuration = configuration
        case let .background(identifier):
            let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
            self.configuration = configuration
        }
        self.resumeDataDirectory = resumeDataDirectory
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        (events, continuation) = AsyncStream.makeStream(of: DownloadEvent.self)
        super.init()
        _ = session
    }
}

// MARK: - DownloadProviderProtocol
extension DownloadProvider: DownloadProviderProtocol {
    public func start(_ request: NetworkRequestProtocol, id: String, allowsCellularAccess: Bool) throws {
        var urlRequest = try URLRequestBuilder.build(from: request)
        urlRequest.allowsCellularAccess = allowsCellularAccess
        removeResumeData(for: id)
        run(session.downloadTask(with: urlRequest), id: id)
    }

    public func pause(id: String) async {
        guard let task = await task(for: id) else { return }
        let resumeData = await task.cancelByProducingResumeData()
        if let resumeData {
            saveResumeData(resumeData, for: id)
        }
    }

    public func resume(id: String, allowsCellularAccess: Bool) throws {
        guard let resumeData = try? Data(contentsOf: resumeDataURL(for: id)) else {
            throw NetworkError.invalidParams
        }
        removeResumeData(for: id)
        run(session.downloadTask(withResumeData: resumeData), id: id)
    }

    public func cancel(id: String) {
        removeResumeData(for: id)
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        }
    }

    public func runningIDs() async -> Set<String> {
        let tasks = await session.allTasks
        return Set(tasks.filter { $0.state == .running }.compactMap(\.taskDescription))
    }

    public func handleBackgroundEvents(completion: @escaping () -> Void) {
        lock.withLock { backgroundCompletion = completion }
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadProvider: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadTask.taskDescription else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let mark = ProgressMark(receivedBytes: totalBytesWritten, expectedBytes: expected, date: Date())
        guard progress[id].map(mark.isWorthReporting(after:)) ?? true else { return }
        progress[id] = mark
        continuation.yield(.progress(id: id, receivedBytes: totalBytesWritten, expectedBytes: expected))
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = downloadTask.taskDescription else { return }
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            continuation.yield(.failed(id: id, error: .httpStatus(response.statusCode)))
            return
        }
        // URLSession deletes `location` as soon as this method returns, so move it synchronously.
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation.yield(.finished(id: id, location: destination))
        } catch {
            continuation.yield(.failed(id: id, error: .fileSystem))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        progress[id] = nil
        // Success and HTTP failures were already reported in `didFinishDownloadingTo`.
        guard let error else { return }
        let nsError = error as NSError
        // Keep what the system hands back after a network failure or a force-quit, so `resume` can
        // continue. A plain user cancel has none, and a pause already saved its own.
        let isUserCancel = nsError.code == NSURLErrorCancelled
            && nsError.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] == nil
        if !isUserCancel, let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            saveResumeData(resumeData, for: id)
        }
        continuation.yield(.failed(id: id, error: Self.networkError(from: error)))
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock {
            defer { backgroundCompletion = nil }
            return backgroundCompletion
        }
        guard let completion else { return }
        DispatchQueue.main.async(execute: completion)
    }
}

// MARK: - Helpers
private extension DownloadProvider {
    func run(_ task: URLSessionDownloadTask, id: String) {
        task.taskDescription = id
        task.resume()
    }

    func task(for id: String) async -> URLSessionDownloadTask? {
        await session.allTasks.lazy
            .compactMap { $0 as? URLSessionDownloadTask }
            .first { $0.taskDescription == id && $0.state == .running }
    }

    func resumeDataURL(for id: String) -> URL {
        resumeDataDirectory.appendingPathComponent("\(id).resume")
    }

    func saveResumeData(_ data: Data, for id: String) {
        try? FileManager.default.createDirectory(at: resumeDataDirectory, withIntermediateDirectories: true)
        try? data.write(to: resumeDataURL(for: id), options: .atomic)
    }

    func removeResumeData(for id: String) {
        try? FileManager.default.removeItem(at: resumeDataURL(for: id))
    }

    /// Maps URLSession errors the same way `NetworkProvider` does.
    static func networkError(from error: Error) -> NetworkError {
        if let error = error as? NetworkError {
            return error
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return .cancelledRequest
        }
        if nsError.domain == NSURLErrorDomain && ConnectionError(rawValue: nsError.code) != nil {
            return .connection
        }
        return .invalidResponse
    }
}

/// A progress event already emitted, kept to throttle the next ones.
private struct ProgressMark {
    let receivedBytes: Int64
    let expectedBytes: Int64?
    let date: Date

    /// At most one event per 1% of the file, or per 0.5 s when the size is unknown or progress is slow.
    func isWorthReporting(after previous: ProgressMark) -> Bool {
        if date.timeIntervalSince(previous.date) >= 0.5 {
            return true
        }
        guard let expectedBytes, expectedBytes > 0 else { return false }
        return Double(receivedBytes - previous.receivedBytes) / Double(expectedBytes) >= 0.01
    }
}

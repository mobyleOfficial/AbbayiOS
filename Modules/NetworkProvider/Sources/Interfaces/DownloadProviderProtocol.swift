//
//  DownloadProviderProtocol.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// Downloads large files straight to disk, with progress, pause/resume and cancellation.
///
/// Every download is identified by a caller-chosen `id`, and everything that happens to it is
/// reported on `events`.
public protocol DownloadProviderProtocol: AnyObject {
    /// Progress, completion and failure of every download. Meant for a single consumer.
    var events: AsyncStream<DownloadEvent> { get }

    /// Starts downloading the request's URL. Discards any resume data previously saved for `id`.
    ///
    /// `allowsCellularAccess: false` keeps the download off every metered network: cellular,
    /// expensive paths (Personal Hotspot) and constrained ones (Low Data Mode). The system holds
    /// the task until an unmetered path is available.
    /// - Throws: `NetworkError` when the request can't be turned into a URL.
    func start(_ request: NetworkRequestProtocol, id: String, allowsCellularAccess: Bool) throws

    /// Stops the download and keeps its resume data on disk. Emits `.failed(id, .cancelledRequest)`.
    func pause(id: String) async

    /// Continues a paused or interrupted download from its saved resume data.
    ///
    /// A resumed download keeps the network settings of the request it was started with: resume
    /// data carries that request and URLSession offers no public way to change it. So with
    /// `allowsCellularAccess: false`, resume data whose request may use a metered network
    /// (cellular, Personal Hotspot or Low Data Mode) is deleted instead and this throws, for the
    /// caller to `start` the download afresh.
    /// - Throws: `NetworkError.invalidParams` when there is no resume data for `id`, or it was
    ///   refused as above.
    func resume(id: String, allowsCellularAccess: Bool) throws

    /// Stops the download and deletes its resume data. Emits `.failed(id, .cancelledRequest)`.
    func cancel(id: String)

    /// The ids of downloads currently running, including ones re-attached after a relaunch.
    func runningIDs() async -> Set<String>

    /// The running downloads whose request may use a metered network: cellular, Personal Hotspot
    /// or Low Data Mode. A download started with `allowsCellularAccess: false` is never among them.
    func runningIDsAllowingMeteredNetworks() async -> Set<String>

    /// Stops these downloads and deletes their resume data, like `cancel(id:)`, but returns only
    /// once each running task has been cancelled, so a download started afterwards with the same
    /// id is not cancelled too. Each still emits `.failed(id, .cancelledRequest)`.
    func cancel(ids: Set<String>) async

    /// Stores the completion handler the system passes to
    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`, and calls it on
    /// the main queue once the session has delivered all its pending events, or right away when
    /// the session already finished delivering them before this was called.
    func handleBackgroundEvents(completion: @escaping () -> Void)
}

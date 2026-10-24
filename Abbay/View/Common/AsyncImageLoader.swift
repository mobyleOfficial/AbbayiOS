//
//  AsyncImageLoader.swift
//  Abbay
//

import Foundation
import NetworkProvider
import UIKit

/// The hosts covers may come from. The README promises networking limited to librivox.org and
/// archive.org, so the loader refuses anything else rather than fetch whatever URL a catalog
/// response carries.
struct CoverHostPolicy {
    static let libriVox = CoverHostPolicy(domains: ["librivox.org", "archive.org"])

    /// Each domain allows itself and its subdomains (`ia800300.us.archive.org`).
    let domains: [String]

    /// HTTPS on an allowed domain. Anything else, including file URLs, is refused.
    func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// Loads remote images (LibriVox covers) through `NetworkProvider`, in front of two caches: decoded
/// images in memory by URL, so a view that comes back on screen shows its image at once, and the
/// downloaded bytes on disk (`CoverDiskCache`), so a cover doesn't download again after a relaunch.
///
/// Concurrent loads of one URL (a Popular card and the details page it opens) share one download.
/// That shared load runs to completion even if every view asking for it leaves the screen, so the
/// cover is cached for the next appearance; the view simply ignores a result it no longer wants.
///
/// URLs outside `CoverHostPolicy` are refused before either cache or the network is touched, and
/// logged. Every failure (refused host, no connection, non-2xx status, a body that isn't an image)
/// comes back as `nil` and is not cached, so the next appearance tries again.
final class AsyncImageLoader {
    enum Policy {
        /// Enough for Popular (30) plus a page of search results (50) and the open details page.
        static let cacheCountLimit = 100
    }

    static let shared = DebugOverrides.coverLoader() ?? AsyncImageLoader()

    private let network: NetworkProviderProtocol
    private let cache: NSCache<NSURL, UIImage>
    private let diskCache: CoverDiskCache?
    private let hosts: CoverHostPolicy
    private let lock = NSLock()
    private var inFlight = [URL: Task<UIImage?, Never>]()

    init(
        network: NetworkProviderProtocol = NetworkProvider(),
        cache: NSCache<NSURL, UIImage> = makeCache(),
        diskCache: CoverDiskCache? = .shared,
        hosts: CoverHostPolicy = .libriVox
    ) {
        self.network = network
        self.cache = cache
        self.diskCache = diskCache
        self.hosts = hosts
    }

    static func makeCache() -> NSCache<NSURL, UIImage> {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = Policy.cacheCountLimit
        return cache
    }

    /// The image already loaded for `url` in memory, without touching the disk or the network.
    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// The image for `url` from memory, disk or the network, decoded for display off the main
    /// thread; nil when it can't be had.
    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        guard hosts.allows(url) else {
            Log.covers.error("Refused a cover outside the host allowlist: \(url.absoluteString, privacy: .private)")
            return nil
        }
        return await sharedLoad(for: url).value
    }

    // MARK: - Private

    /// The load already running for `url`, or a new one. It leaves `inFlight` when it ends, so a
    /// failed load is retried by the next caller.
    private func sharedLoad(for url: URL) -> Task<UIImage?, Never> {
        lock.withLock {
            if let running = inFlight[url] { return running }
            // Registered before the lock is released, so the task can't end and unregister first.
            let task = Task {
                let image = await self.load(url)
                self.lock.withLock { self.inFlight[url] = nil }
                return image
            }
            inFlight[url] = task
            return task
        }
    }

    private func load(_ url: URL) async -> UIImage? {
        if let image = await imageFromDisk(for: url) { return image }

        let request = LibriVoxRequests.cover(for: url)
        guard let response: NetworkResponse<Data> = try? await network.makeRequest(request),
              (200..<300).contains(response.statusCode),
              let decoded = UIImage(data: response.content)
        else { return nil }

        diskCache?.store(response.content, for: url)
        return await remember(decoded, for: url)
    }

    /// The stored cover, or nil; an entry that no longer decodes is dropped so the download
    /// replaces it.
    private func imageFromDisk(for url: URL) async -> UIImage? {
        guard let diskCache, let data = diskCache.data(for: url) else { return nil }
        guard let decoded = UIImage(data: data) else {
            diskCache.remove(for: url)
            return nil
        }
        Log.covers.debug("Cover served from disk: \(url.absoluteString, privacy: .private)")
        return await remember(decoded, for: url)
    }

    private func remember(_ decoded: UIImage, for url: URL) async -> UIImage {
        let image = await decoded.byPreparingForDisplay() ?? decoded
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

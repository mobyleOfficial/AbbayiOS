//
//  AsyncImageLoader.swift
//  Abbay
//

import Foundation
import NetworkProvider
import UIKit

/// Loads remote images (LibriVox covers) through `NetworkProvider` and keeps them in memory by
/// URL, so a view that comes back on screen shows its image at once instead of loading again.
///
/// Every failure (no connection, non-2xx status, a body that isn't an image, cancellation before
/// the body arrives) comes back as `nil` and is not cached, so the next appearance tries again.
final class AsyncImageLoader {
    enum Policy {
        /// Enough for Popular (30) plus a page of search results (50) and the open details page.
        static let cacheCountLimit = 100
    }

    static let shared = AsyncImageLoader()

    private let network: NetworkProviderProtocol
    private let cache: NSCache<NSURL, UIImage>

    init(network: NetworkProviderProtocol = NetworkProvider(), cache: NSCache<NSURL, UIImage> = makeCache()) {
        self.network = network
        self.cache = cache
    }

    static func makeCache() -> NSCache<NSURL, UIImage> {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = Policy.cacheCountLimit
        return cache
    }

    /// The image already loaded for `url`, without touching the network.
    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// The cached image, or the one at `url`, decoded for display off the main thread.
    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }

        let request = LibriVoxRequests.cover(for: url)
        guard let response: NetworkResponse<Data> = try? await network.makeRequest(request),
              (200..<300).contains(response.statusCode),
              let decoded = UIImage(data: response.content)
        else { return nil }

        let image = await decoded.byPreparingForDisplay() ?? decoded
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

//
//  UITestCoverNetwork.swift
//  Abbay
//

#if DEBUG
import Foundation
import NetworkProvider
import UIKit

/// Answers cover requests from memory for `LaunchArgument.stubCovers`: after `delay`, a generated
/// image, so UI tests can catch the cover loading and then loaded. With `-stubCoversOffline` every
/// request fails, so only the disk cache can produce a cover.
struct UITestCoverNetwork: NetworkProviderProtocol {
    /// On archive.org, so the loader's host allowlist lets it through.
    static let coverURL = URL(string: "https://archive.org/services/img/ui-test-stub")
        ?? URL(fileURLWithPath: "/dev/null/cover.jpg")

    /// Apart from the real covers' cache, so UI tests never touch it.
    static var diskDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("UITestCovers", isDirectory: true)
    }

    /// Long enough for a UI test to open the details page and compare two frames while loading: a
    /// simulator under XCUITest takes 5-6 s from the Search tab appearing to the details page.
    static let delay = Duration.seconds(12)

    let isOffline: Bool
    var delay: Duration = Self.delay

    func makeRequest<T: Decodable>(_ request: NetworkRequestProtocol) async throws -> NetworkResponse<T> {
        throw NetworkError.connection
    }

    func makeRequest(_ request: NetworkRequestProtocol) async throws -> NetworkResponse<Data> {
        guard !isOffline else { throw NetworkError.connection }
        try await Task.sleep(for: delay)
        return NetworkResponse(statusCode: 200, headers: [:], content: Self.image())
    }

    /// A green square with a darker inner square, so "loaded" is obvious on screen.
    private static func image() -> Data {
        let side: CGFloat = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.pngData { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIColor.black.withAlphaComponent(0.3).setFill()
            context.fill(CGRect(x: side / 4, y: side / 4, width: side / 2, height: side / 2))
        }
    }
}
#endif

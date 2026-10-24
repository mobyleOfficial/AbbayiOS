//
//  ResumeDataInspectorTests.swift
//  NetworkProviderTests
//

@testable import NetworkProvider
import XCTest

/// Resume data built the way URLSession writes it (checked against real resume data from a
/// URLSession download on macOS 27: a keyed archive of a dictionary under
/// `NSKeyedArchiveRootObjectKey`, whose request entries are keyed archives of `NSMutableURLRequest`).
final class ResumeDataInspectorTests: XCTestCase {
    func test_requestHoldingEveryMeteredNetwork_doesNotAllowThem() {
        let data = ResumeDataFixture.make(allowsCellular: false, allowsExpensive: false, allowsConstrained: false)

        XCTAssertEqual(ResumeDataInspector.allowsMeteredNetworks(data), false)
    }

    /// A Wi-Fi-only download started before #134: cellular off, hotspot and Low Data Mode still on.
    func test_requestFromBefore134_allowsMeteredNetworks() {
        let data = ResumeDataFixture.make(allowsCellular: false, allowsExpensive: true, allowsConstrained: true)

        XCTAssertEqual(ResumeDataInspector.allowsMeteredNetworks(data), true)
    }

    func test_onlyConstrainedAllowed_allowsMeteredNetworks() {
        let data = ResumeDataFixture.make(allowsCellular: false, allowsExpensive: false, allowsConstrained: true)

        XCTAssertEqual(ResumeDataInspector.allowsMeteredNetworks(data), true)
    }

    func test_rootKeyVariant_isReadToo() {
        let data = ResumeDataFixture.make(
            allowsCellular: false,
            allowsExpensive: true,
            allowsConstrained: false,
            rootKey: NSKeyedArchiveRootObjectKey
        )

        XCTAssertEqual(ResumeDataInspector.allowsMeteredNetworks(data), true)
    }

    func test_unreadableData_isUnknown() {
        XCTAssertNil(ResumeDataInspector.allowsMeteredNetworks(Data([1, 2, 3])))
        let noRequest = ResumeDataFixture.archive(["NSURLSessionDownloadURL": "https://example.com/a.mp3"] as NSDictionary)
        XCTAssertNil(ResumeDataInspector.allowsMeteredNetworks(noRequest))
    }
}

/// Builds resume data in URLSession's format, around a request with the given network flags.
enum ResumeDataFixture {
    static func make(
        allowsCellular: Bool,
        allowsExpensive: Bool,
        allowsConstrained: Bool,
        rootKey: String = ResumeDataInspector.rootKey
    ) -> Data {
        var request = URLRequest(url: URL(string: "https://archive.org/download/x/ch0.mp3")!)
        request.allowsCellularAccess = allowsCellular
        request.allowsExpensiveNetworkAccess = allowsExpensive
        request.allowsConstrainedNetworkAccess = allowsConstrained
        let archivedRequest = archive(request as NSURLRequest, rootKey: rootKey)
        let dictionary: NSDictionary = [
            "NSURLSessionDownloadURL": "https://archive.org/download/x/ch0.mp3",
            "NSURLSessionResumeBytesReceived": 1000,
            "NSURLSessionResumeOriginalRequest": archivedRequest,
            "NSURLSessionResumeCurrentRequest": archivedRequest
        ]
        return archive(dictionary, rootKey: rootKey)
    }

    static func archive(_ object: Any, rootKey: String = ResumeDataInspector.rootKey) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(object, forKey: rootKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }
}

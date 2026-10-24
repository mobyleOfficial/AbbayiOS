//
//  ResumeDataInspector.swift
//  NetworkProvider
//

import Foundation

/// Reads the request a download's resume data would continue with, so a resume can be refused when
/// that request would use a network the caller no longer allows.
///
/// Resume data is an `NSKeyedArchiver` archive of a dictionary whose
/// `NSURLSessionResumeOriginalRequest` and `NSURLSessionResumeCurrentRequest` entries are
/// themselves archived `NSURLRequest`s. The format is not public API: anything that doesn't decode
/// gives `nil`, and the caller keeps the resume data.
enum ResumeDataInspector {
    static let requestKeys = ["NSURLSessionResumeOriginalRequest", "NSURLSessionResumeCurrentRequest"]
    /// The root key URLSession writes. `NSKeyedArchiveRootObjectKey` ("root") is tried too.
    static let rootKey = "NSKeyedArchiveRootObjectKey"

    private static let dictionaryClasses: [AnyClass] = [
        NSDictionary.self, NSString.self, NSData.self, NSNumber.self, NSDate.self, NSURL.self, NSArray.self
    ]

    /// Whether the archived request may use cellular, an expensive path (Personal Hotspot) or a
    /// constrained one (Low Data Mode); `nil` when the data can't be read.
    static func allowsMeteredNetworks(_ resumeData: Data) -> Bool? {
        guard let dictionary = root(of: resumeData, classes: dictionaryClasses) as? [String: Any] else { return nil }
        let requests = requestKeys.compactMap { key in
            (dictionary[key] as? Data).flatMap { root(of: $0, classes: [NSURLRequest.self]) as? URLRequest }
        }
        guard !requests.isEmpty else { return nil }
        return requests.contains(where: allowsMeteredNetworks)
    }

    static func allowsMeteredNetworks(_ request: URLRequest) -> Bool {
        request.allowsCellularAccess || request.allowsExpensiveNetworkAccess || request.allowsConstrainedNetworkAccess
    }

    private static func root(of data: Data, classes: [AnyClass]) -> Any? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(of: classes, forKey: rootKey)
            ?? unarchiver.decodeObject(of: classes, forKey: NSKeyedArchiveRootObjectKey)
    }
}

//
//  PathTemplate.swift
//  NetworkProvider
//
//  Created on 21/10/26.
//

import Foundation

/// Replaces `{name}` placeholders in an endpoint with percent-encoded values.
enum PathTemplate {
    static func resolve(_ template: String, with params: [String: String]?) throws -> String {
        let params = params ?? [:]
        var usedNames = Set<String>()
        var result = ""
        var remainder = template[...]

        while let match = remainder.firstMatch(of: #/\{([A-Za-z0-9_]+)\}/#) {
            result += remainder[..<match.range.lowerBound]
            let name = String(match.output.1)
            guard let value = params[name] else {
                throw NetworkError.missingPathParam(name: name)
            }
            guard !value.isEmpty,
                  let encoded = value.addingPercentEncoding(withAllowedCharacters: .pathSegmentAllowed) else {
                throw NetworkError.invalidParams
            }
            result += encoded
            usedNames.insert(name)
            remainder = remainder[match.range.upperBound...]
        }
        result += remainder

        if let unused = params.keys.sorted().first(where: { !usedNames.contains($0) }) {
            throw NetworkError.unusedPathParam(name: unused)
        }
        return result
    }
}

private extension CharacterSet {
    /// Characters allowed in one path segment: the URL path set minus the separators.
    static let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
}

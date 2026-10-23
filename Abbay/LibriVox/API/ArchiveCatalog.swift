//
//  ArchiveCatalog.swift
//  Abbay
//

import Foundation

/// Turns archive.org item data into the app's book and chapters. Pure functions, no networking.
enum ArchiveCatalog {
    /// The derivative every LibriVox item has, one file per section.
    static let chapterFormat = "64Kbps MP3"

    /// archive.org titles are often "Title, by Author". The suffix is dropped only when it names
    /// the item's own creator, so a title that merely contains ", by " is left alone.
    static func cleanTitle(_ title: String, creator: String?) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let creator, !creator.isEmpty else { return trimmed }
        let suffix = ", by " + creator
        guard trimmed.count > suffix.count,
              trimmed.lowercased().hasSuffix(suffix.lowercased())
        else { return trimmed }
        return String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
    }

    /// `"10:40"` and `"1:02:03"` (colon-separated) or `"640.5"` (seconds). Nil when unreadable.
    static func seconds(fromLength length: String?) -> Double? {
        guard let text = length?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        guard text.contains(":") else { return Double(text).flatMap { $0 >= 0 ? $0 : nil } }
        var total = 0.0
        for part in text.split(separator: ":", omittingEmptySubsequences: false) {
            guard let value = Double(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// The name LibriVox's `author=` filter matches: "Lewis Carroll" and "Carroll, Lewis" are both
    /// "Carroll". Nil for a missing or blank creator.
    static func lastName(of creator: String?) -> String? {
        guard let creator = creator?.trimmingCharacters(in: .whitespaces), !creator.isEmpty else { return nil }
        if let comma = creator.firstIndex(of: ",") {
            let surname = creator[..<comma].trimmingCharacters(in: .whitespaces)
            return surname.isEmpty ? nil : surname
        }
        return creator.split(separator: " ").last.map(String.init)
    }

    /// `"3/12"` and `"3"` are both 3.
    static func trackNumber(_ track: String?) -> Int? {
        guard let first = track?.split(separator: "/").first else { return nil }
        return Int(first.trimmingCharacters(in: .whitespaces))
    }

    /// The 64 kb MP3s, by numeric track and then by name (numeric-aware), for items with no
    /// LibriVox match.
    static func chapterFiles(_ files: [ArchiveMetadataDTO.File]) -> [ArchiveMetadataDTO.File] {
        files
            .filter { $0.format == chapterFormat && !($0.name ?? "").isEmpty }
            .sorted { lhs, rhs in
                let left = trackNumber(lhs.track) ?? .max
                let right = trackNumber(rhs.track) ?? .max
                if left != right { return left < right }
                return (lhs.name ?? "").localizedStandardCompare(rhs.name ?? "") == .orderedAscending
            }
    }

    /// A chapter built from the file alone: its `title`, else the file name without extension.
    static func fallbackSection(_ file: ArchiveMetadataDTO.File, identifier: String) -> LibriVoxBook.Section? {
        guard let name = file.name, !name.isEmpty, let base = URL(string: LibriVoxRequests.downloadEndpoint) else {
            return nil
        }
        let stem = (name as NSString).deletingPathExtension
        let title = file.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LibriVoxBook.Section(
            title: (title?.isEmpty == false ? title : nil) ?? stem,
            seconds: seconds(fromLength: file.length) ?? 0,
            listenURL: base.appendingPathComponent(identifier).appendingPathComponent(name)
        )
    }
}

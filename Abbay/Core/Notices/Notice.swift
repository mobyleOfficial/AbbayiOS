//
//  Notice.swift
//  Abbay
//

import Foundation

/// Something that went wrong and that the user should hear about (#115), shown by `NoticeCenter`
/// as a banner. Only failures worth interrupting for get a case: a failed import, a book or
/// chapter that won't play, a lost save. A transient player status change does not.
///
/// Recoverable cases say how to recover: a moved file is fixed by importing it again, an
/// undownloaded chapter by downloading the book.
enum Notice: Equatable {
    /// Some of the picked files couldn't be imported, by file name.
    case importFailed(fileNames: [String])
    /// An imported file is no longer where its bookmark points: it was moved, renamed or deleted.
    case fileMissing(title: String)
    /// A book that won't play for any other reason: no URL, or a file that's there but unreadable.
    case playbackFailed
    /// The audio session couldn't be activated. It usually clears on its own.
    case audioUnavailable
    /// A LibriVox chapter that isn't downloaded, played without a connection.
    case streamingOffline
    /// A LibriVox chapter that failed for another reason.
    case chapterFailed
    /// A Core Data save failed, so the latest change (an import, a position) may be lost.
    case saveFailed
    /// *Find chapters* heard no chapter headings in the book's audio: it keeps no chapters.
    case noChaptersFound
    /// *Find chapters* couldn't search the audio: no speech model for its language, or the engine
    /// failed. Trying again may work.
    case chapterSearchFailed

    /// How many file names an import message lists before it says "and N more".
    static let listedFileNameLimit = 3

    var message: String {
        switch self {
        case .importFailed(let fileNames):
            return Self.importMessage(fileNames: fileNames)
        case .fileMissing(let title):
            return Localizable.noticeFileMissing.localized(with: title)
        case .playbackFailed:
            return Localizable.noticePlaybackFailed.localized
        case .audioUnavailable:
            return Localizable.noticeAudioUnavailable.localized
        case .streamingOffline:
            return Localizable.noticeStreamingOffline.localized
        case .chapterFailed:
            return Localizable.noticeChapterFailed.localized
        case .saveFailed:
            return Localizable.noticeSaveFailed.localized
        case .noChaptersFound:
            return Localizable.noticeNoChaptersFound.localized
        case .chapterSearchFailed:
            return Localizable.noticeChapterSearchFailed.localized
        }
    }

    /// What a book is called in a message: its title, or its file name when the file had none.
    static func title(of book: AudioModel) -> String {
        if !book.title.isEmpty { return book.title }
        return book.fileURL?.deletingPathExtension().lastPathComponent ?? String()
    }

    /// One file is named on its own; several are counted, then listed up to `listedFileNameLimit`.
    private static func importMessage(fileNames: [String]) -> String {
        guard fileNames.count > 1 else {
            return Localizable.noticeImportFailedOne.localized(with: fileNames.first ?? String())
        }
        var listed = Array(fileNames.prefix(listedFileNameLimit))
        let remaining = fileNames.count - listed.count
        if remaining > 0 {
            listed.append(Localizable.noticeImportFailedMore.localized(with: remaining))
        }
        let list = ListFormatter.localizedString(byJoining: listed)
        return Localizable.noticeImportFailedMany.localized(with: fileNames.count, list)
    }
}

//
//  Localizable.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/04/24.
//

import Foundation

enum Localizable: String {
    case libraryTitle
    case emptyLibraryTitle
    case chapterSelectionTitle
    case chapterCount
    case delete
    case addMenu
    case importFile
    case browseFreeAudiobooks
    case importAFile
    case popularOnLibriVox
    case librivoxSearchPrompt
    case searchTitle
    case searchOffline
    case searchFailed
    case noResults
    case downloadedTag
    case downloadPaused
    case downloadingProgress
    case download
    case play
    case pause
    case chaptersCount
    case librivoxCredit
    case more
    case largeDownloadTitle
    case largeDownloadMessage
    case continueDownload
    case waitForWiFi
    case waiting
    case chapterDownloadFailed
    case detailsFailed
    case retry
    case rowChapter
    case rowTimeLeft
    case libraryTab
    case searchTab
    case librarySearchPrompt
    case closePlayer
    case miniPlayerSubtitle
    case chapterProgress
    case openPlayer
    case nextChapterAction
    case restartChapterAction
    case carPlayEmptyLibraryTitle
    case carPlayEmptyLibrarySubtitle
    case noticeImportFailedOne
    case noticeImportFailedMany
    case noticeImportFailedMore
    case noticeFileMissing
    case noticePlaybackFailed
    case noticeAudioUnavailable
    case noticeStreamingOffline
    case noticeChapterFailed
    case noticeSaveFailed
    case noticeDismiss
    case noChaptersTitle
    case noChaptersMessage
    // Settings
    case settingsTitle
    case done
    case settingsPlayback
    case defaultSpeed
    case defaultSpeedFooter
    case skipBack
    case skipForward
    case skipSeconds
    case skipFooter
    case settingsDownloads
    case cellularDownloads
    case cellularAsk
    case cellularAlways
    case cellularWifiOnly
    case cellularFooter
    case spaceUsed
    case calculating
    case deleteFinished
    case deleteFinishedFooter
    case deleteFinishedNone
    case deleteFinishedTitle
    case deleteFinishedMessage
    case cancel
    case settingsLanguage
    case languageSystem
    case languageFooter
    case settingsAbout
    case privacyPolicy
    case version
    case librivoxAbout
    case openSourceLicenses
    case licensesBody
    case licensesContent
    case siriAudioStatus
    case audioStatusOK
    case audioStatusUnavailable
    case audioStatusOKDetail
    case audioStatusUnavailableDetail
    // Speed and skip
    case playbackSpeed
    case speedDecrease
    case speedIncrease
    case speedPresets
    case speedSetDefault
    case speedIsDefault
    case skipBackAction
    case skipForwardAction
}

extension Localizable {
    var localized: String {
        NSLocalizedString(rawValue, bundle: AbbayBundle.value, comment: String())
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: localized, arguments)
    }
}

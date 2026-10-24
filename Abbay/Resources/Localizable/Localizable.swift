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
    case timestamp
    case delete
    case addMenu
    case browseLibriVox
    case importFile
    case browseFreeAudiobooks
    case importAFile
    case searchPrompt
    case inYourLibrary
    case onLibriVox
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
    case chaptersCount
    case librivoxCredit
    case more
    case largeDownloadTitle
    case largeDownloadMessage
    case continueDownload
    case waitForWiFi
    case waiting
    case detailsFailed
    case retry
    case rowChapter
    case rowTimeLeft
}

extension Localizable {
    var localized: String {
        NSLocalizedString(rawValue, bundle: AbbayBundle.value, comment: String())
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: localized, arguments)
    }
}

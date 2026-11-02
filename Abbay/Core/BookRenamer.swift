//
//  BookRenamer.swift
//  Abbay
//

import Foundation

extension Notification.Name {
    /// A book was renamed (#322). `object` is the book's URL, `userInfo[BookRenamer.titleKey]` the
    /// title it now shows. Posted on the main thread.
    static let bookTitleDidChange = Notification.Name("abbay.bookTitleDidChange")
}

/// Renames a book from the player or a library cell (#322): saves the name
/// (`RenameAudioUseCase`, which rewrites Siri's snapshot), hands the title to the player if the
/// book is loaded, and tells the screens holding a copy (`.bookTitleDidChange`). CarPlay re-reads
/// the library on the snapshot's change.
@MainActor
struct BookRenamer {
    static let titleKey = "title"

    var rename: RenameAudioUseCaseProtocol = RenameAudioUseCase()
    var playback: PlaybackCenter?
    var notificationCenter: NotificationCenter = .default

    /// Imported books only: a LibriVox book's title is the catalog's.
    static func canRename(_ book: AudioModel) -> Bool {
        !book.isLibriVox && book.url != nil
    }

    func rename(_ book: AudioModel, to name: String) {
        guard Self.canRename(book), let url = book.url,
              let title = rename.execute(title: name, bookURL: url)
        else { return }
        playback?.replaceTitle(title, ofBookAt: url)
        notificationCenter.post(name: .bookTitleDidChange, object: url, userInfo: [Self.titleKey: title])
    }
}

//
//  MultiFileQueue.swift
//  Abbay
//

import AVFoundation
import Foundation

/// Plays a book made of one file per chapter (LibriVox) on the `Player`'s `AVQueuePlayer`.
///
/// Everything outside this type speaks **book time** (the spec: "the position is a single
/// number"). This type maps it to (chapter file, offset) with `BookTimeline`, keeps the current
/// chapter plus the next one queued so the hand-off between files is gapless, and maps the
/// item-relative time back to book time.
final class MultiFileQueue {
    // MARK: - Properties
    private let player: AVQueuePlayer
    private let chapters: [ChapterModel]
    private let timeline: BookTimeline
    private let bookID: String
    private let downloadsRoot: URL
    private let prioritizer: ChapterPrioritizing
    private let onBookEnd: () -> Void

    private(set) var currentIndex = 0
    /// Items this queue put on the player, by chapter index. Lets the end-of-item notification be
    /// matched to a chapter and ignored when it belongs to an item we already replaced.
    private var items: [Int: AVPlayerItem] = [:]
    /// The book time last asked for, until its seek completes. Seeks are async and an item that
    /// isn't ready yet reports zero, so without this `saveTime()` right after a seek would store the
    /// chapter's start (or zero) instead of where the listener actually is.
    private var pendingBookTime: Double?
    private var seekGeneration = 0
    private var endObserver: NSObjectProtocol?

    /// Book-wide time: the chapter's start plus the offset into its file.
    var bookTime: Double {
        if let pendingBookTime { return pendingBookTime }
        guard chapters.indices.contains(currentIndex) else { return 0 }
        let offset = player.currentTime().seconds
        return chapters[currentIndex].startTime + (offset.isFinite ? offset : 0)
    }

    // MARK: - Init
    init(
        player: AVQueuePlayer,
        chapters: [ChapterModel],
        bookID: String,
        downloadsRoot: URL,
        prioritizer: ChapterPrioritizing,
        onBookEnd: @escaping () -> Void
    ) {
        self.player = player
        self.chapters = chapters
        self.timeline = BookTimeline(chapters: chapters)
        self.bookID = bookID
        self.downloadsRoot = downloadsRoot
        self.prioritizer = prioritizer
        self.onBookEnd = onBookEnd

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            self?.itemDidPlayToEnd(item)
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - Seeking
    /// Seeks within the current file when the target is in the loaded chapter, otherwise loads the
    /// target chapter's file at the right offset.
    func seek(toBookTime bookTime: Double) {
        guard !chapters.isEmpty else { return }
        let position = timeline.position(at: bookTime)
        if position.chapterIndex == currentIndex, items[currentIndex] != nil {
            seekCurrentItem(to: position)
        } else {
            load(chapterIndex: position.chapterIndex, offset: position.offset)
        }
    }

    // MARK: - Helpers
    private func load(chapterIndex index: Int, offset: Double) {
        guard let item = makeItem(for: index) else { return }
        currentIndex = index
        items = [index: item]
        // `replaceCurrentItem(with:)` on a queue player swaps only the head and would leave the
        // previous chapter's successor queued, so rebuild the whole queue.
        player.removeAllItems()
        player.insert(item, after: nil)
        seekCurrentItem(to: BookTimeline.Position(chapterIndex: index, offset: offset))
        enqueue(chapterIndex: index + 1, after: item)
        updateActionAtItemEnd()
        prioritizer.prioritize(chapterIndex: index, ofBookID: bookID)
    }

    private func seekCurrentItem(to position: BookTimeline.Position) {
        seekGeneration += 1
        let generation = seekGeneration
        pendingBookTime = timeline.bookTime(chapterIndex: position.chapterIndex, offset: position.offset)
        player.seek(to: CMTime(seconds: position.offset, preferredTimescale: 600)) { [weak self] finished in
            DispatchQueue.main.async {
                // Only the latest seek may clear the pending time: an earlier one completing
                // (or being cancelled) must not expose the stale position in between.
                guard let self, finished, generation == self.seekGeneration else { return }
                self.pendingBookTime = nil
            }
        }
    }

    private func enqueue(chapterIndex index: Int, after previous: AVPlayerItem) {
        guard let item = makeItem(for: index) else { return }
        items[index] = item
        player.insert(item, after: previous)
    }

    private func makeItem(for index: Int) -> AVPlayerItem? {
        guard chapters.indices.contains(index),
              let url = LibriVoxIdentity.playableURL(for: chapters[index], bookID: bookID, root: downloadsRoot)
        else { return nil }
        return AVPlayerItem(url: url)
    }

    /// At the last chapter there is nothing to advance to: pausing keeps the finished item current,
    /// so book time stays at the end instead of falling back to the chapter's start.
    private func updateActionAtItemEnd() {
        player.actionAtItemEnd = currentIndex >= chapters.count - 1 ? .pause : .advance
    }

    private func itemDidPlayToEnd(_ item: AVPlayerItem) {
        guard items[currentIndex] === item else { return }
        let next = currentIndex + 1
        guard chapters.indices.contains(next), let nextItem = items[next] else {
            onBookEnd()
            return
        }
        // The queue player has already moved on to `nextItem`; just keep our bookkeeping in step
        // and queue the file after it.
        items[currentIndex] = nil
        currentIndex = next
        pendingBookTime = nil
        enqueue(chapterIndex: next + 1, after: nextItem)
        updateActionAtItemEnd()
        prioritizer.prioritize(chapterIndex: next, ofBookID: bookID)
    }
}

//
//  MultiFileQueue.swift
//  Abbay
//

import AVFoundation
import Foundation
import os

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
    /// The chapter being played failed to load or play; `isStreaming` when it isn't downloaded.
    /// On main. A queued chapter failing ahead of time is reported only once it becomes current.
    private let onItemFailed: (_ isStreaming: Bool) -> Void

    private(set) var currentIndex = 0
    /// Items this queue put on the player, by chapter index. Lets the end-of-item notification be
    /// matched to a chapter and ignored when it belongs to an item we already replaced.
    private var items: [Int: AVPlayerItem] = [:]
    /// The book time last asked for, until its seek completes. Seeks are async and an item that
    /// isn't ready yet reports zero, so without this `saveTime()` right after a seek would store the
    /// chapter's start (or zero) instead of where the listener actually is.
    private(set) var pendingBookTime: Double?
    /// The item `pendingBookTime` was asked of. Once the player has moved off it the pending time
    /// is stale, whether or not its seek completed.
    private var pendingItem: AVPlayerItem?
    private(set) var seekGeneration = 0
    /// The last book time computed, for when the player holds no item of ours (nothing loaded yet,
    /// or the queue emptied), rather than falling back to a chapter's start or zero.
    private var lastBookTime: Double = 0
    private var endObserver: NSObjectProtocol?
    /// One status observation per item in `items`.
    private var failureObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    /// Book-wide time: the chapter's start plus the offset into its file.
    ///
    /// The chapter is the one whose item is current, not `currentIndex`: the queue player moves on
    /// to the next file before the `.main`-queue end-of-item handler updates `currentIndex`, and in
    /// that window the old chapter's start plus the new item's ~0 would jump back a chapter (#118).
    var bookTime: Double {
        let item = player.currentItem
        if let pendingBookTime, let item, item === pendingItem {
            lastBookTime = pendingBookTime
            return pendingBookTime
        }
        guard let item, let index = items.first(where: { $0.value === item })?.key,
              chapters.indices.contains(index)
        else { return lastBookTime }
        let offset = player.currentTime().seconds
        lastBookTime = chapters[index].startTime + (offset.isFinite ? offset : 0)
        return lastBookTime
    }

    // MARK: - Init
    init(
        player: AVQueuePlayer,
        chapters: [ChapterModel],
        bookID: String,
        downloadsRoot: URL,
        prioritizer: ChapterPrioritizing,
        onBookEnd: @escaping () -> Void,
        onItemFailed: @escaping (_ isStreaming: Bool) -> Void = { _ in }
    ) {
        self.player = player
        self.chapters = chapters
        self.timeline = BookTimeline(chapters: chapters)
        self.bookID = bookID
        self.downloadsRoot = downloadsRoot
        self.prioritizer = prioritizer
        self.onBookEnd = onBookEnd
        self.onItemFailed = onItemFailed

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

    // MARK: - Failures
    /// Whether the chapter being played failed, e.g. an undownloaded chapter played offline.
    var currentItemFailed: Bool {
        items[currentIndex]?.status == .failed
    }

    /// Loads the chapter that holds `bookTime` again with a fresh item: a retry after a failure.
    func reload(atBookTime bookTime: Double) {
        guard !chapters.isEmpty else { return }
        let position = timeline.position(at: bookTime)
        load(chapterIndex: position.chapterIndex, offset: position.offset)
    }

    // MARK: - Helpers
    private func load(chapterIndex index: Int, offset: Double) {
        failureObservations = [:]
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
        pendingItem = player.currentItem
        player.seek(to: CMTime(seconds: position.offset, preferredTimescale: 600)) { [weak self] finished in
            DispatchQueue.main.async {
                self?.finishSeek(generation: generation, finished: finished)
            }
        }
    }

    /// A seek's completion, on main. Internal for tests: a real seek on an item that never loads
    /// doesn't complete.
    func finishSeek(generation: Int, finished: Bool) {
        // Only the latest seek may clear the pending time: an earlier one completing
        // (or being cancelled) must not expose the stale position in between.
        guard generation == seekGeneration else { return }
        // Cleared even when `finished` is false (#130): the latest seek is interrupted only by
        // something other than a seek, so no later completion would clear it and the displayed time
        // would freeze. The item's own time is where the listener really is.
        clearPendingSeek()
    }

    private func clearPendingSeek() {
        pendingBookTime = nil
        pendingItem = nil
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
        let item = AVPlayerItem(url: url)
        failureObservations[ObjectIdentifier(item)] = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { self?.itemFailed(item) }
        }
        return item
    }

    private func isStreaming(chapterIndex index: Int) -> Bool {
        !LibriVoxIdentity.isDownloaded(chapters[index], bookID: bookID, root: downloadsRoot)
    }

    /// Only the chapter being played is the listener's problem.
    private func itemFailed(_ item: AVPlayerItem) {
        guard items[currentIndex] === item else { return }
        reportFailure(of: item, chapterIndex: currentIndex)
    }

    private func reportFailure(of item: AVPlayerItem, chapterIndex index: Int) {
        let error = item.error as NSError?
        let isStreaming = isStreaming(chapterIndex: index)
        Log.player.error(
            """
            chapter \(index, privacy: .public) failed: streaming=\(isStreaming, privacy: .public), \
            \(error?.domain ?? "", privacy: .public) \(error?.code ?? 0, privacy: .public)
            """
        )
        onItemFailed(isStreaming)
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
        failureObservations[ObjectIdentifier(item)] = nil
        items[currentIndex] = nil
        currentIndex = next
        clearPendingSeek()
        enqueue(chapterIndex: next + 1, after: nextItem)
        updateActionAtItemEnd()
        prioritizer.prioritize(chapterIndex: next, ofBookID: bookID)
        // It failed while queued, when it wasn't the listener's problem yet; now it is.
        if nextItem.status == .failed {
            reportFailure(of: nextItem, chapterIndex: next)
        }
    }
}

//
//  PlayerProtocol.swift
//  Abbay
//

import AVFoundation
import Combine

protocol PlayerProtocol {
    var url: URL? { get }
    var currentTime: Double { get }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { get }
    var playUrlSubjectPublisher: AnyPublisher<AudioModel, Never> { get }
    /// Whether the player is playing (or buffering towards it), on the main queue, without
    /// duplicates. See `Player.isPlaying(status:reason:)`.
    /// Unlike the time publisher it also fires on a pause, which stops the ticks.
    var isPlayingPublisher: AnyPublisher<Bool, Never> { get }

    func play(_ model: inout AudioModel)
    func pause()
    func forward(withSeconds seconds: Double)
    func backward(withSeconds seconds: Double)
    /// Whether `url` is loaded and playing, by the same rule as `isPlayingPublisher`.
    func isPlaying(_ url: URL?) -> Bool
    func seek(_ seconds: Double)
    func cleanup()
    /// Stops and forgets the loaded book (it was deleted), so `url` becomes nil. Unlike `cleanup`,
    /// which runs at termination, the player stays usable: the next `play` loads normally.
    func unload()
    func skipToNextChapter()
    func skipToPreviousChapter()
    /// Plays a chapter of the loaded book from where it was left (#299); the chapter already
    /// playing just keeps playing.
    @discardableResult
    func playChapter(at index: Int) -> Bool
    /// Where `playChapter(at:)` would start chapter `index` of `book`, for loading a book there.
    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double
    /// The loaded book's speed; normal speed when nothing is loaded.
    var playbackRate: Double { get }
    /// Sets the loaded book's speed, saves it for that book, and applies it at once when playing.
    /// It holds across pause and resume, seeks and chapter files.
    func setPlaybackRate(_ rate: Double)
    /// Abbay's own volume, 0–1, under the system volume. One level for every book.
    var volume: Double { get }
    /// Sets and saves Abbay's volume, applied at once whether playing or not. Ends any fade.
    func setVolume(_ volume: Double)
    /// The sleep timer's fade (#332), 0–1 under Abbay's volume: 1 when not fading. Never saved.
    var fadeLevel: Double { get }
    /// Dims the player to `level` (clamped to 0–1) of Abbay's volume, without saving anything.
    func setFadeLevel(_ level: Double)
    /// Fires on main when the loaded book plays to its end (single-file or multi-file).
    var bookEndPublisher: AnyPublisher<Void, Never> { get }
    /// Fires on main when a multi-file book's chapter file plays to its end and the next one takes
    /// over by itself: the real chapter boundary, which can come before the listed end (#332).
    var chapterEndPublisher: AnyPublisher<Void, Never> { get }
    /// The loaded book got new chapters (or lost them): found in its audio, or removed again. Only
    /// an imported single-file book's chapters can change; anything else is ignored.
    func replaceChapters(_ chapters: [ChapterModel], ofBookAt url: URL)
    /// The loaded book was renamed (#322): Now Playing and Siri's donations use the new title.
    func replaceTitle(_ title: String, ofBookAt url: URL)
}

/// For players with no speed or volume control, or saved chapter positions (test doubles that
/// predate them).
extension PlayerProtocol {
    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double {
        book.chapters.indices.contains(index) ? book.chapters[index].resumeTime : 0
    }

    var playbackRate: Double { PlaybackSpeed.normal }

    func setPlaybackRate(_ rate: Double) {}

    var volume: Double { BookVolume.full }

    func setVolume(_ volume: Double) {}

    var fadeLevel: Double { 1 }

    func setFadeLevel(_ level: Double) {}

    var bookEndPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    var chapterEndPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }

    func replaceChapters(_ chapters: [ChapterModel], ofBookAt url: URL) {}

    func replaceTitle(_ title: String, ofBookAt url: URL) {}
}

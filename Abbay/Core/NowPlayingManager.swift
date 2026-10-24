//
//  NowPlayingManager.swift
//  Abbay
//
//  Manages Now Playing info and remote control commands
//

import MediaPlayer
import os
import UIKit

final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private var player: PlayerProtocol?
    private var model: AudioModel?
    /// The Settings skip amounts, in seconds. The lock screen and CarPlay draw the arrows from the
    /// commands' `preferredIntervals`; the handlers jump by these.
    private(set) var skipBackwardInterval = SkipInterval.standard.seconds
    private(set) var skipForwardInterval = SkipInterval.standard.seconds

    /// Read-only view of the audio currently associated with the playback session.
    /// Set via `setPlayer(_:currentAudio:)`. Consumed by App Intents to gate
    /// commands that require something to be playing (Pause / Next / Previous).
    var currentAudio: AudioModel? { model }

    private init() {
        setupRemoteCommandCenter()
    }

    func setPlayer(_ player: PlayerProtocol, currentAudio: AudioModel?) {
        self.player = player
        self.model = currentAudio
    }

    // MARK: - Now Playing Info
    /// `playbackRate` is the book's speed: the system extrapolates elapsed time by it, so the lock
    /// screen's clock runs at the real speed between updates.
    func updateNowPlaying(for audio: AudioModel, currentTime: Double, isPlaying: Bool, playbackRate: Double = 1) {
        var nowPlayingInfo = [String: Any]()

        // Basic info
        nowPlayingInfo[MPMediaItemPropertyTitle] = audio.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = audio.artist.isEmpty ? audio.albumName : audio.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = audio.albumName

        // Timing info
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = audio.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = playbackRate

        // Artwork
        if let imageData = audio.imageData, let image = UIImage(data: imageData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        // Chapter info
        if let currentChapter = audio.currentChapter(for: currentTime) {
            nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = "Chapter \(currentChapter + 1) of \(audio.chapters.count)"
            nowPlayingInfo[MPNowPlayingInfoPropertyChapterNumber] = currentChapter
            nowPlayingInfo[MPNowPlayingInfoPropertyChapterCount] = audio.chapters.count
            nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused

        Log.nowPlaying.debug(
            "updated: \(audio.title, privacy: .private) at \(currentTime, privacy: .public)s, playing=\(isPlaying, privacy: .public)"
        )
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Drop the playback gate alongside the system info. `currentAudio` is what
        // PauseAbbayIntent, NextChapterIntent, PreviousChapterIntent and PlayChapterIntent
        // check, so leaving it set here makes Siri answer "Paused." when nothing is playing.
        //
        // Only `model` is cleared. `player` must NOT be, because this method is reachable
        // from `Player.deinit` -> `cleanup()`, and that deinit is itself triggered by the
        // `player` assignment inside `setPlayer`. Writing `player` here re-enters a property
        // whose write is still in progress and traps on Swift's exclusive-access check.
        // Leaving it is also more correct: a dying player must not unregister its successor.
        // The remote play/toggle handlers guard on `model`, so they fail correctly anyway.
        model = nil
        Log.nowPlaying.debug("cleared")
    }

    // MARK: - Remote Command Center
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        setupPlaybackCommands(commandCenter)
        setupSkipCommands(commandCenter)
        setupTrackCommands(commandCenter)
        setupSeekCommand(commandCenter)
        setupPlaybackRateCommand(commandCenter)
        Log.nowPlaying.debug("remote command center configured")
    }

    private func setupPlaybackCommands(_ commandCenter: MPRemoteCommandCenter) {
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self, let player = self.player, var model = self.model else {
                return .commandFailed
            }
            player.play(&model)
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self, let player = self.player else {
                return .commandFailed
            }
            player.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause() ?? .commandFailed
        }
    }

    /// The lock screen's and CarPlay's toggle. `Player.isPlaying(_:)` counts waiting to play while
    /// buffering as playing (as the in-app play/pause does), so a toggle while buffering pauses.
    func togglePlayPause() -> MPRemoteCommandHandlerStatus {
        guard let player, var model else { return .commandFailed }
        if player.isPlaying(model.url) {
            player.pause()
        } else {
            player.play(&model)
        }
        return .success
    }

    /// Sets the lock screen's and CarPlay's skip amounts (Settings). Their arrows show the number.
    func setSkipIntervals(backward: Double, forward: Double) {
        skipBackwardInterval = backward
        skipForwardInterval = forward
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: backward)]
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: forward)]
    }

    func skipForward() -> MPRemoteCommandHandlerStatus {
        guard let player else { return .commandFailed }
        player.forward(withSeconds: skipForwardInterval)
        return .success
    }

    func skipBackward() -> MPRemoteCommandHandlerStatus {
        guard let player else { return .commandFailed }
        player.backward(withSeconds: skipBackwardInterval)
        return .success
    }

    private func setupSkipCommands(_ commandCenter: MPRemoteCommandCenter) {
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward() ?? .commandFailed
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardInterval)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward() ?? .commandFailed
        }
    }

    /// A speed picked outside the app (an accessory's or the system's speed control) becomes the
    /// loaded book's speed, as if picked in the speed sheet.
    func changePlaybackRate(to rate: Double) -> MPRemoteCommandHandlerStatus {
        guard let player, model != nil else { return .commandFailed }
        player.setPlaybackRate(rate)
        return .success
    }

    private func setupPlaybackRateCommand(_ commandCenter: MPRemoteCommandCenter) {
        let command = commandCenter.changePlaybackRateCommand
        command.isEnabled = true
        command.supportedPlaybackRates = PlaybackSpeed.presets.map { NSNumber(value: $0) }
        command.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            return self?.changePlaybackRate(to: Double(event.playbackRate)) ?? .commandFailed
        }
    }

    private func setupTrackCommands(_ commandCenter: MPRemoteCommandCenter) {
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            player.skipToNextChapter()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let player = self?.player else { return .commandFailed }
            player.skipToPreviousChapter()
            return .success
        }
    }

    private func setupSeekCommand(_ commandCenter: MPRemoteCommandCenter) {
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let player = self.player else {
                return .commandFailed
            }
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                player.seek(event.positionTime)
            }
            return .success
        }
    }
}

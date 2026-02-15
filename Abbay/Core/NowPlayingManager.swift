//
//  NowPlayingManager.swift
//  Abbay
//
//  Manages Now Playing info and remote control commands
//

import MediaPlayer
import UIKit

final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private var player: PlayerProtocol?
    private var model: AudioModel?

    private init() {
        setupRemoteCommandCenter()
    }

    func setPlayer(_ player: PlayerProtocol, currentAudio: AudioModel?) {
        self.player = player
        self.model = currentAudio
    }

    // MARK: - Now Playing Info
    func updateNowPlaying(for audio: AudioModel, currentTime: Double, isPlaying: Bool) {
        var nowPlayingInfo = [String: Any]()

        // Basic info
        nowPlayingInfo[MPMediaItemPropertyTitle] = audio.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = audio.artist.isEmpty ? audio.albumName : audio.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = audio.albumName

        // Timing info
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = audio.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // Artwork
        if let imageData = audio.imageData, let image = UIImage(data: imageData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        // Chapter info
        let currentChapter = audio.currentChapter(for: currentTime)
        if !audio.chapters.isEmpty {
            nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = "Chapter \(currentChapter + 1) of \(audio.chapters.count)"
            nowPlayingInfo[MPNowPlayingInfoPropertyChapterNumber] = currentChapter
            nowPlayingInfo[MPNowPlayingInfoPropertyChapterCount] = audio.chapters.count
            nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused

        print("📻 NowPlaying: Updated - \(audio.title) at \(currentTime)s, playing: \(isPlaying)")
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("📻 NowPlaying: Cleared")
    }

    // MARK: - Remote Command Center
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        setupPlaybackCommands(commandCenter)
        setupSkipCommands(commandCenter)
        setupTrackCommands(commandCenter)
        setupSeekCommand(commandCenter)
        print("📻 NowPlaying: Remote Command Center configured")
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
            guard let self = self, let player = self.player, var model = self.model else {
                return .commandFailed
            }
            if player.isPlaying(model.url) {
                player.pause()
            } else {
                player.play(&model)
            }
            return .success
        }
    }

    private func setupSkipCommands(_ commandCenter: MPRemoteCommandCenter) {
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let self = self, let player = self.player else {
                return .commandFailed
            }
            if let command = event.command as? MPSkipIntervalCommand,
               let interval = command.preferredIntervals.first {
                player.forward(withSeconds: interval.doubleValue)
            } else {
                player.forward(withSeconds: 15)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let self = self, let player = self.player else {
                return .commandFailed
            }
            if let command = event.command as? MPSkipIntervalCommand,
               let interval = command.preferredIntervals.first {
                player.backward(withSeconds: interval.doubleValue)
            } else {
                player.backward(withSeconds: 15)
            }
            return .success
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

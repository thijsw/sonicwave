import Foundation
import MediaPlayer
import AppKit

/// Bridges `PlayerModel` to the system Now Playing center and remote command
/// center: publishes metadata/artwork/elapsed time, and routes media keys /
/// Control Center transport back into the app. The single writer to
/// `MPNowPlayingInfoCenter`. See docs/06-system-integration.md.
@MainActor
final class NowPlayingCenter {
    // Intent callbacks, set by PlayerModel.
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    private let infoCenter = MPNowPlayingInfoCenter.default()

    init() {
        configureCommands()
    }

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.onPlay?(); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?(); return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?(); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?(); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrevious?(); return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.onSeek?(event.positionTime)
            return .success
        }
        // Commands we don't support are left disabled by default.
        center.ratingCommand.isEnabled = false
        center.likeCommand.isEnabled = false
    }

    /// Update the static metadata + transport state for the current track.
    func update(track: Song?, state: PlaybackState, position: TimeInterval, duration: TimeInterval) {
        guard let track else {
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .stopped
            return
        }
        var info = infoCenter.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = track.album ?? ""
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = mpPlaybackState(state)
    }

    /// Update only the elapsed time / rate (cheap, called on the position tick).
    func updateProgress(position: TimeInterval, duration: TimeInterval, state: PlaybackState) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = mpPlaybackState(state)
    }

    func updateArtwork(_ image: NSImage?) {
        guard let image, var info = infoCenter.nowPlayingInfo else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        info[MPMediaItemPropertyArtwork] = artwork
        infoCenter.nowPlayingInfo = info
    }

    private func mpPlaybackState(_ state: PlaybackState) -> MPNowPlayingPlaybackState {
        switch state {
        case .playing: return .playing
        case .paused: return .paused
        case .buffering: return .playing
        case .stopped: return .stopped
        }
    }
}

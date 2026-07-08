import Foundation

/// System remote commands (media keys, Now Playing widget, headphone
/// buttons) → transport intents. Wired once at init.
extension PlayerModel {
    func wireRemoteCommands() {
        guard let nowPlaying else { return }
        nowPlaying.onPlay = { [weak self] in
            guard let self, self.state != .playing else { return }
            self.togglePlayPause()
        }
        nowPlaying.onPause = { [weak self] in
            guard let self, self.state == .playing else { return }
            self.togglePlayPause()
        }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.next() }
        nowPlaying.onPrevious = { [weak self] in self?.previous() }
        nowPlaying.onSeek = { [weak self] time in self?.seek(to: time) }
    }
}

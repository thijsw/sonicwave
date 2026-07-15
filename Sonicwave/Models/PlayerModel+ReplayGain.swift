import Foundation

/// Volume normalization: the linear pre-mixer gain a track should play at,
/// per the user's ReplayGain mode. Computed at hand-off (hard start and
/// gapless pre-buffer) and baked into the span's buffers by PlaybackService —
/// mode changes apply from the next track. Math lives on ReplayGainMode.
extension PlayerModel {
    /// Settings → Playback picker stores the same key; default off.
    var replayGainMode: ReplayGainMode {
        ReplayGainMode(rawValue: UserDefaults.standard.string(forKey: "replayGainMode") ?? "") ?? .off
    }

    func replayGain(for song: Song) -> Float {
        replayGainMode.linearGain(for: song.replayGain)
    }
}

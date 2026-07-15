import Foundation

enum PlaybackState: Equatable, Sendable {
    case stopped
    case buffering
    case playing
    case paused
}

enum RepeatMode: String, Sendable, CaseIterable {
    case off, all, one
}

/// Volume normalization (Settings → Playback, "replayGainMode" default off):
/// `track` evens out mixed queues, `album` preserves intra-album dynamics.
enum ReplayGainMode: String, Sendable, CaseIterable {
    case off, track, album

    /// Linear pre-mixer gain for a song under this mode. dB → 10^(dB/20),
    /// clamped so gain × peak never clips full scale, and capped at +12 dB
    /// as a sanity bound against absurd tags. Missing data falls back to the
    /// other scope's tags, then to unity.
    func linearGain(for info: ReplayGainInfo?) -> Float {
        guard self != .off, let info else { return 1 }
        let decibels = self == .album
            ? info.albumGain ?? info.trackGain
            : info.trackGain ?? info.albumGain
        guard let decibels else { return 1 }
        var gain = pow(10.0, decibels / 20.0)
        let peak = self == .album
            ? info.albumPeak ?? info.trackPeak
            : info.trackPeak ?? info.albumPeak
        if let peak, peak > 0 { gain = min(gain, 1.0 / peak) }
        return Float(min(gain, 4.0))
    }
}

import Foundation

/// Events emitted by `PlaybackService` and consumed by `PlayerModel` on the
/// main actor. See docs/03-playback-engine.md.
enum PlaybackEvent: Sendable {
    case stateChanged(PlaybackState)
    case position(time: TimeInterval, duration: TimeInterval)
    /// The current track finished playing naturally (not via stop/skip).
    case ended
    case failed(String)
}

/// Server-side transcoding preferences, read from the same UserDefaults keys
/// the Settings UI (`ConnectionModel`) writes. The playback service reads these
/// at load time to decide the `stream` parameters.
struct TranscodePrefs: Sendable {
    var format: String?
    var maxBitRate: Int?

    static func current(_ defaults: UserDefaults = .standard) -> TranscodePrefs {
        guard defaults.bool(forKey: "transcodeEnabled") else {
            return TranscodePrefs(format: nil, maxBitRate: nil)
        }
        let format = defaults.string(forKey: "transcodeFormat") ?? "mp3"
        let bitrate = defaults.integer(forKey: "transcodeMaxBitRate")
        return TranscodePrefs(format: format, maxBitRate: bitrate == 0 ? 320 : bitrate)
    }
}

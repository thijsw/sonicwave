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

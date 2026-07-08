import SwiftUI

/// Play + Shuffle buttons for a collection header (album/playlist detail).
struct PlayShuffleButtons: View {
    let tracks: [Song]
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Button {
            player.play(tracks: tracks)
        } label: { Label("Play", systemImage: "play.fill") }
        .disabled(tracks.isEmpty)

        Button {
            player.play(tracks: tracks.shuffled())
        } label: { Label("Shuffle", systemImage: "shuffle") }
        .disabled(tracks.isEmpty)
    }
}

/// "12 songs · 42:17" — the header subtitle for a track collection.
func trackSummary(_ tracks: [Song]) -> String {
    let songs = "\(tracks.count) song\(tracks.count == 1 ? "" : "s")"
    let total = tracks.reduce(0) { $0 + ($1.duration ?? 0) }
    return total > 0 ? "\(songs) · \(formatTime(total))" : songs
}

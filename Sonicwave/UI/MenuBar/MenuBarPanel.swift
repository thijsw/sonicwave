import SwiftUI

/// Compact Now Playing panel shown from the menu-bar item (window style),
/// modeled on the macOS Music / Control Center dropdown. Shares the same
/// PlayerModel as the main window. See docs/04-ui-ux.md.
struct MenuBarPanel: View {
    @Environment(PlayerModel.self) private var player
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 12) {
            ArtworkView(coverArt: player.currentTrack?.coverArt, size: 160, cornerRadius: 10)
                .shadow(radius: 4, y: 2)

            VStack(spacing: 2) {
                Text(player.currentTrack?.title ?? "Not Playing")
                    .font(.headline).lineLimit(1)
                Text(player.currentTrack?.artist ?? "—")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }

            Slider(value: Binding(
                get: { scrubValue ?? player.position },
                set: { scrubValue = $0 }
            ), in: 0...max(player.duration, 1), onEditingChanged: { editing in
                if !editing, let value = scrubValue {
                    player.seek(to: value)
                    scrubValue = nil
                }
            })
            .disabled(player.currentTrack == nil)
            .accessibilityLabel("Playback position")

            HStack(spacing: 28) {
                Button { player.previous() } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel("Previous")
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.next() } label: { Image(systemName: "forward.fill") }
                    .accessibilityLabel("Next")
            }
            .buttonStyle(.borderless)
            .disabled(player.currentTrack == nil)
        }
        .padding(16)
        .frame(width: 240)
    }
}

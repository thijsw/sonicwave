import SwiftUI

/// Persistent now-playing header pinned to the bottom of the main window:
/// artwork, track info, scrubber, and transport controls. See docs/04-ui-ux.md.
struct NowPlayingBar: View {
    @Environment(PlayerModel.self) private var player
    /// Holds the in-progress scrub position so we seek once on release, not on
    /// every value change (seeking re-opens the stream — see docs/03).
    @State private var scrubValue: Double?

    var body: some View {
        @Bindable var player = player
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                ArtworkView(coverArt: player.currentTrack?.coverArt, size: 44, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? "Not Playing")
                        .font(.callout).bold().lineLimit(1)
                    Text(player.currentTrack?.artist ?? "—")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: 200, alignment: .leading)

                transport

                scrubber

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary).font(.caption)
                        .accessibilityHidden(true)
                    Slider(value: $player.volume, in: 0...1)
                        .frame(width: 90)
                        .accessibilityLabel("Volume")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Button { player.previous() } label: { Image(systemName: "backward.fill") }
                .accessibilityLabel("Previous")
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.next() } label: { Image(systemName: "forward.fill") }
                .accessibilityLabel("Next")
        }
        .buttonStyle(.borderless)
        .disabled(player.currentTrack == nil)
    }

    private var scrubber: some View {
        HStack(spacing: 8) {
            Text(formatTime(scrubValue ?? player.position)).font(.caption2).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            Slider(value: Binding(
                get: { scrubValue ?? player.position },
                set: { scrubValue = $0 }
            ), in: 0...max(player.duration, 1), onEditingChanged: { editing in
                if !editing, let value = scrubValue {
                    player.seek(to: value)
                    scrubValue = nil
                }
            })
            .frame(minWidth: 160)
            .accessibilityLabel("Playback position")
            Text(formatTime(player.duration)).font(.caption2).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 38, alignment: .leading)
        }
        .disabled(player.currentTrack == nil)
    }
}

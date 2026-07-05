import SwiftUI

/// Compact Now Playing panel shown from the menu-bar item (window style),
/// sharing the main window's PlayerModel and the design language of the
/// Now Playing inspector: slim accent scrubber with elapsed/total times, and
/// a transport row with the accent-filled play circle flanked by shuffle and
/// repeat toggles. See docs/04-ui-ux.md.
struct MenuBarPanel: View {
    @Environment(PlayerModel.self) private var player
    /// In-progress scrub position; seek once on release (see docs/03).
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 0) {
            ArtworkView(coverArt: player.currentTrack?.coverArt, size: 208, cornerRadius: 10,
                        placeholderSymbol: "waveform")
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)

            Text(player.currentTrack?.title ?? "Not Playing")
                .font(.headline).lineLimit(1)
                .padding(.top, 12)
            Text(player.currentTrack?.artist ?? "—")
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                .padding(.top, 1)

            SlimSlider(
                value: Binding(
                    get: { scrubValue ?? player.position },
                    set: { scrubValue = $0 }
                ),
                range: 0...max(player.duration, 1),
                fill: .accentColor,
                trackHeight: 5,
                thumbSize: 12
            ) { editing in
                if !editing, let value = scrubValue {
                    player.seek(to: value)
                    scrubValue = nil
                }
            }
            .disabled(player.currentTrack == nil)
            .accessibilityLabel("Playback position")
            .padding(.top, 10)

            HStack {
                Text(formatTime(scrubValue ?? player.position))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .padding(.top, 2)

            transport
                .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 240)
    }

    /// Shuffle · prev / play / next · repeat — the inspector's transport row,
    /// sized down for the compact panel.
    private var transport: some View {
        HStack(spacing: 14) {
            Button { player.shuffle.toggle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .foregroundStyle(player.shuffle ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Shuffle")

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Previous")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .accentColor.opacity(0.45), radius: 5, y: 2)
                    .contentShape(Circle())
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Next")

            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .foregroundStyle(player.repeatMode != .off ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Repeat")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .disabled(player.currentTrack == nil)
    }
}

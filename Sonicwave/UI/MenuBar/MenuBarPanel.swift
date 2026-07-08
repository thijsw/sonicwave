import SwiftUI

/// Compact Now Playing panel shown from the menu-bar item (window style),
/// sharing the main window's PlayerModel and the design language of the
/// Now Playing inspector: slim accent scrubber with elapsed/total times, and
/// a transport row with the accent-filled play circle flanked by shuffle and
/// repeat toggles. See docs/04-ui-ux.md.
struct MenuBarPanel: View {
    @Environment(PlayerModel.self) private var player

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

            ScrubberBar()
                .disabled(player.currentTrack == nil)
                .padding(.top, 10)

            TransportCluster(size: .compact)
                .disabled(player.currentTrack == nil)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 240)
    }
}

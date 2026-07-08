import SwiftUI

/// Shuffle · prev / play / next · repeat — the transport row shared by the Now
/// Playing panel and the menu-bar panel: the play button is the one prominent
/// (accent-filled) control, shuffle/repeat are subordinate toggles (accent when
/// active), Music-style. Two fixed sizes, nothing else differs.
struct TransportCluster: View {
    enum Size {
        /// The Now Playing panel's row.
        case panel
        /// Sized down for the compact menu-bar panel.
        case compact
    }
    var size: Size = .panel
    @Environment(PlayerModel.self) private var player

    private var metrics: Metrics { size == .panel ? .panel : .compact }

    var body: some View {
        HStack(spacing: metrics.spacing) {
            toggle("shuffle", label: "Shuffle", active: player.shuffle) {
                player.shuffle.toggle()
            }

            skip("backward.fill", label: "Previous") { player.previous() }

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: metrics.playIcon))
                    .foregroundStyle(.white)
                    .frame(width: metrics.playFrame, height: metrics.playFrame)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .accentColor.opacity(0.45), radius: metrics.shadowRadius, y: metrics.shadowY)
                    .contentShape(Circle())
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            skip("forward.fill", label: "Next") { player.next() }

            toggle(player.repeatMode == .one ? "repeat.1" : "repeat",
                   label: "Repeat", active: player.repeatMode != .off) {
                player.cycleRepeat()
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }

    private func toggle(_ symbol: String, label: String, active: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.toggleIcon))
                .frame(width: metrics.toggleFrame, height: metrics.toggleFrame)
                .contentShape(Circle())
        }
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .accessibilityLabel(label)
    }

    private func skip(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.skipIcon))
                .frame(width: metrics.skipFrame, height: metrics.skipFrame)
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }

    private struct Metrics {
        let spacing, toggleIcon, toggleFrame, skipIcon, skipFrame: CGFloat
        let playIcon, playFrame, shadowRadius, shadowY: CGFloat

        static let panel = Metrics(spacing: 20, toggleIcon: 13, toggleFrame: 28,
                                   skipIcon: 18, skipFrame: 36,
                                   playIcon: 19, playFrame: 48, shadowRadius: 6, shadowY: 3)
        static let compact = Metrics(spacing: 14, toggleIcon: 12, toggleFrame: 24,
                                     skipIcon: 16, skipFrame: 32,
                                     playIcon: 17, playFrame: 42, shadowRadius: 5, shadowY: 2)
    }
}

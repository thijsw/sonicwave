import SwiftUI

/// Slim accent scrubber with elapsed/total captions beneath, shared by the Now
/// Playing panel and the menu-bar panel. The scrub position is held locally
/// while dragging; the player seeks once on release (see docs/03).
struct ScrubberBar: View {
    @Environment(PlayerModel.self) private var player
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 0) {
            SlimSlider(
                value: Binding(
                    get: { scrubValue ?? player.position },
                    set: { scrubValue = $0 }
                ),
                range: 0...max(player.duration, 1),
                fill: .accentColor,
                trackHeight: 5,
                thumbSize: 12,
                accessibilityValueText:
                    "\(formatTime(scrubValue ?? player.position)) of \(formatTime(player.duration))"
            ) { editing in
                if !editing, let value = scrubValue {
                    player.seek(to: value)
                    scrubValue = nil
                }
            }
            .accessibilityLabel("Playback position")

            HStack {
                Text(formatTime(scrubValue ?? player.position))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
        }
    }
}

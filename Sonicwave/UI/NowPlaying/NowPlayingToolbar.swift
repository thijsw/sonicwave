import SwiftUI

/// The now-playing experience lives in the window's top toolbar (a radical move
/// from the classic bottom bar): transport controls sit at the leading edge, an
/// "LCD" now-playing display is centered, and volume sits trailing. These views
/// are wired into the toolbar from `RootView`. See docs/04-ui-ux.md.

// MARK: - Transport (leading)

/// Shuffle, previous, play/pause, next and repeat — the transport cluster shown
/// at the leading edge of the toolbar, next to the window controls.
///
/// Following Apple's guidance (only one prominent control), the primary
/// prev/play/next cluster is bright (`.primary`) with the play button emphasized
/// in a circle, while shuffle/repeat read as subordinate toggles (`.secondary`,
/// accent when active) — matching the design's hierarchy. SF Symbols are sized
/// with `.font(.system(size:))` rather than `.resizable()` so they stay crisp.
struct TransportControls: View {
    @Environment(PlayerModel.self) private var player

    /// Size of the emphasized play/pause circle.
    private let playDiameter: CGFloat = 32

    var body: some View {
        // One even 14pt rhythm across the whole cluster (matching the design),
        // rather than the primary trio being looser than the flanking toggles.
        HStack(spacing: 14) {
            // Subordinate: shuffle.
            Button { player.shuffle.toggle() } label: {
                Image(systemName: "shuffle").font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(player.shuffle ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Shuffle")

            // Primary cluster: prev / play / next — bright, evenly weighted, with
            // the play button emphasized in a translucent circle.
            HStack(spacing: 14) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 14))
                }
                .accessibilityLabel("Previous")

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .frame(width: playDiameter, height: playDiameter)
                        .background(.primary.opacity(0.08), in: Circle())
                        .overlay { Circle().strokeBorder(.primary.opacity(0.12)) }
                        .contentShape(Circle())
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 14))
                }
                .accessibilityLabel("Next")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(player.currentTrack == nil)

            // Subordinate: repeat.
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(player.repeatMode != .off ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Repeat")
        }
    }
}

// MARK: - Now-playing display (centered)

/// The centered "LCD" capsule: artwork, title/artist and an inline scrubber with
/// elapsed / remaining time. Replaces the info+scrubber portion of the old
/// bottom bar.
struct NowPlayingDisplay: View {
    @Environment(PlayerModel.self) private var player
    /// Holds the in-progress scrub position so we seek once on release, not on
    /// every value change (seeking re-opens the stream — see docs/03).
    @State private var scrubValue: Double?

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(coverArt: player.currentTrack?.coverArt, size: 32, cornerRadius: 5)
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.currentTrack?.title ?? "Not Playing")
                        .font(.caption).fontWeight(.semibold).lineLimit(1)
                    Text(player.currentTrack?.artist ?? "—")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                scrubber
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 44)
        // Flexible up to the design's 430pt, but able to shrink so the unified
        // toolbar doesn't push the trailing items into its overflow menu on
        // narrower windows. monospaced-digit times keep it from reflowing.
        .frame(minWidth: 280, idealWidth: 430, maxWidth: 430)
        // Recessed "LCD screen" look: a dark translucent fill with a soft inner
        // shadow from the top and a hairline highlight along the edge — the
        // subtle depth (matching the design's inset box-shadows) that makes the
        // capsule read as a little inset display rather than a flat chip.
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.30)
                    .shadow(.inner(color: .black.opacity(0.45), radius: 2.5, y: 1)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
    }

    private var scrubber: some View {
        HStack(spacing: 7) {
            Text(formatTime(scrubValue ?? player.position))
                .font(.system(size: 9.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            SlimSlider(
                value: Binding(
                    get: { scrubValue ?? player.position },
                    set: { scrubValue = $0 }
                ),
                range: 0...max(player.duration, 1),
                fill: .accentColor
            ) { editing in
                if !editing, let value = scrubValue {
                    player.seek(to: value)
                    scrubValue = nil
                }
            }
            .accessibilityLabel("Playback position")
            Text(remaining)
                .font(.system(size: 9.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .disabled(player.currentTrack == nil)
    }

    /// Time left in the track, shown as a negative countdown like classic iTunes.
    private var remaining: String {
        let left = player.duration - (scrubValue ?? player.position)
        guard player.currentTrack != nil, left > 0 else { return "—" }
        return "-" + formatTime(left)
    }
}

// MARK: - Volume (trailing)

/// Speaker icon and volume slider, shown at the trailing edge of the toolbar.
struct VolumeControl: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        @Bindable var player = player
        HStack(spacing: 7) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary).font(.caption)
                .accessibilityHidden(true)
            SlimSlider(value: $player.volume, range: 0...1,
                       fill: .primary.opacity(0.55), thumbSize: 9)
                .frame(width: 70)
                .accessibilityLabel("Volume")
        }
    }
}

// MARK: - Slim slider

/// A slim, refined slider — thin track, colored fill, small white thumb — that
/// matches the design's LCD scrubber and volume bar far better than the chunky
/// default macOS `Slider`. Dragging updates `value`; `onEditingChanged(false)`
/// fires on release so the scrubber can seek once rather than continuously.
struct SlimSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var fill: Color = .accentColor
    var trackHeight: CGFloat = 3
    var thumbSize: CGFloat = 8
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var editing = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let r = thumbSize / 2
            let usable = max(w - thumbSize, 0.0001)
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let thumbX = r + fraction * usable

            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.16))
                    .frame(height: trackHeight)
                Capsule().fill(fill)
                    .frame(width: thumbX, height: trackHeight)
                Circle().fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                    .offset(x: thumbX - r)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !editing { editing = true; onEditingChanged(true) }
                        let f = min(max((g.location.x - r) / usable, 0), 1)
                        value = range.lowerBound + f * span
                    }
                    .onEnded { _ in
                        editing = false
                        onEditingChanged(false)
                    }
            )
        }
        // A taller invisible hit area than the thin visual track, so it's easy to
        // grab (and so drags near it don't fall through to the draggable bar).
        .frame(height: 16)
    }
}

import SwiftUI

/// The now-playing experience lives in the window's top toolbar (a radical move
/// from the classic bottom bar): transport controls sit at the leading edge, an
/// "LCD" now-playing display is centered, and volume sits trailing. These views
/// are wired into the toolbar from `RootView`. See docs/04-ui-ux.md.

// MARK: - Transport (above the sidebar)

/// Previous, play/pause and next — the transport cluster shown in the toolbar
/// strip above the sidebar, right next to the window controls (the classic
/// iTunes corner). Shuffle and repeat live in the Now Playing panel.
///
/// Following Apple's guidance (only one prominent control), prev/next are
/// bright (`.primary`) with the play button emphasized in an accent-filled
/// circle. SF Symbols are sized with `.font(.system(size:))` rather than
/// `.resizable()` so they stay crisp.
struct TransportControls: View {
    @Environment(PlayerModel.self) private var player

    /// Size of the emphasized play/pause circle.
    private let playDiameter: CGFloat = 32

    var body: some View {
        HStack(spacing: 14) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14))
            }
            .accessibilityLabel("Previous")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .frame(width: playDiameter, height: playDiameter)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .accentColor.opacity(0.45), radius: 3, y: 1)
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
    }
}

// MARK: - Now-playing display (centered)

/// The centered "LCD" capsule: artwork, centered title with artist — album
/// beneath, elapsed / total time trailing, and a thin accent progress bar along
/// the bottom edge. Clicking it toggles the Now Playing panel (where the full
/// scrubber lives).
struct NowPlayingDisplay: View {
    @Environment(PlayerModel.self) private var player
    @AppStorage("showUpNext") private var showUpNext = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            ArtworkView(coverArt: player.currentTrack?.coverArt, size: 30, cornerRadius: 5)
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)

            VStack(spacing: 1) {
                Text(player.currentTrack?.title ?? "Not Playing")
                    .font(.caption).fontWeight(.semibold).lineLimit(1)
                Text(subtitle)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            if player.currentTrack != nil {
                Text("\(formatTime(player.position)) / \(formatTime(player.duration))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 44)
        // Flexible up to 560pt, but with a restrained ideal width: the unified
        // toolbar lays principal items out at their ideal size, and an ideal
        // that only fits on wide windows shoves the trailing items (or the LCD
        // itself) into the overflow menu once the inspector is open.
        // monospaced-digit times keep it from reflowing.
        .frame(minWidth: 260, idealWidth: 400, maxWidth: 560)
        // Recessed "LCD screen" look: a dark translucent fill with a soft inner
        // shadow from the top and a hairline highlight along the edge — the
        // subtle depth (matching the design's inset box-shadows) that makes the
        // capsule read as a little inset display rather than a flat chip.
        // The progress hairline lives inside the background stack and is
        // clipped there with the capsule fill — clipping at the outer view
        // level let the bar's square end poke out of the rounded corner.
        .background {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.30)
                        .shadow(.inner(color: .black.opacity(0.45), radius: 2.5, y: 1)))
                // Playback progress as a hairline along the LCD's bottom edge.
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * progressFraction, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(hovering ? 0.22 : 0.10), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            // The panel is only relevant while something is playing or queued.
            if player.currentTrack != nil || !player.upNext.isEmpty {
                showUpNext.toggle()
            }
        }
        .onHover { hovering = $0 }
        .help(showUpNext ? "Hide Now Playing" : "Show Now Playing")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Now Playing")
    }

    private var subtitle: String {
        guard let track = player.currentTrack else { return "—" }
        let artist = track.artist ?? "—"
        if let album = track.album, !album.isEmpty { return "\(artist) — \(album)" }
        return artist
    }

    private var progressFraction: CGFloat {
        guard player.currentTrack != nil, player.duration > 0 else { return 0 }
        return min(max(player.position / player.duration, 0), 1)
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

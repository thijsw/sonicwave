import SwiftUI
import UniformTypeIdentifiers

/// The Now Playing / Up Next panel, shown as an inspector on the trailing edge:
/// a hero card for the current track (artwork, metadata, scrubber, transport)
/// above the upcoming queue with drag-to-reorder, hover-to-remove and
/// play-from-here. See docs/04-ui-ux.md.
struct NowPlayingPanel: View {
    @Environment(PlayerModel.self) private var player

    // No empty state: the panel is only presented when something is playing
    // or queued (RootView gates the inspector on that).
    var body: some View {
        VStack(spacing: 0) {
            if let current = player.currentTrack {
                // Priority so the full-bleed square hero keeps its
                // width-sized height; the queue list takes what's left
                // instead of compressing the artwork.
                CurrentTrackCard(song: current)
                    .layoutPriority(1)
                Divider()
            }
            queue
        }
        // With a hero, extend to the window's very top: the inspector has
        // no toolbar items, so its slice of the toolbar is dead space —
        // the artwork fills it, showing through the toolbar material.
        .ignoresSafeArea(player.currentTrack != nil ? .container : SafeAreaRegions(),
                         edges: .top)
    }

    private var queue: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.caption.weight(.bold))
                    .kerning(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Spacer()
                if !player.upNext.isEmpty {
                    Button("Clear") { player.clearUpNext() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Clear Up Next")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if player.upNext.isEmpty {
                Text("Nothing up next")
                    .foregroundStyle(.secondary).font(.callout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dropDestination(for: DraggedTrack.self) { items, _ in
                        let songs = items.compactMap(\.song)
                        guard !songs.isEmpty else { return false }
                        player.enqueue(songs)
                        return true
                    }
            } else {
                // The ForEach holds only the upcoming slice (no conditional
                // rows — those break the List's row-drag reordering); its
                // local indices map back to queue offsets via `base`.
                let base = (player.currentIndex ?? -1) + 1
                List {
                    // NOTE: no tap gestures / contentShape on these rows —
                    // they claim the mouse-down and kill .onMove row dragging.
                    // Play-from-here is the hover button and the context menu.
                    // Positional identity: the same song can sit in the queue
                    // twice, and duplicate ids make SwiftUI coalesce rows
                    // (shared hover state, callbacks bound to the first
                    // instance, phantom removals).
                    ForEach(Array(player.upNext.enumerated()), id: \.offset) { pair in
                        QueueRow(song: pair.element,
                                 onPlay: { player.playFromQueue(at: base + pair.offset) },
                                 onRemove: { player.removeFromQueue(at: base + pair.offset) })
                            .contextMenu {
                                Button("Play") { player.playFromQueue(at: base + pair.offset) }
                                Button("Remove", role: .destructive) {
                                    player.removeFromQueue(at: base + pair.offset)
                                }
                            }
                            .listRowSeparator(.hidden)
                            // Zero row insets: the row's own 8pt padding is
                            // the hover-highlight bleed, putting content at
                            // ~16pt — aligned with the header and hero meta.
                            .listRowInsets(EdgeInsets())
                    }
                    .onMove { offsets, destination in
                        player.moveQueue(from: IndexSet(offsets.map { $0 + base }),
                                         to: destination + base)
                    }
                    // External drops (rows dragged from any track table)
                    // insert at the drop position; internal reorders still go
                    // through .onMove.
                    .onInsert(of: [.json]) { position, providers in
                        insertDropped(providers, at: base + position)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// Decode `DraggedTrack` payloads from dropped item providers (in order)
    /// and insert their songs at the given queue index.
    private func insertDropped(_ providers: [NSItemProvider], at index: Int) {
        Task {
            var songs: [Song] = []
            for provider in providers {
                let data: Data? = await withCheckedContinuation { continuation in
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
                        continuation.resume(returning: data)
                    }
                }
                if let data,
                   let dragged = try? JSONDecoder().decode(DraggedTrack.self, from: data),
                   let song = dragged.song {
                    songs.append(song)
                }
            }
            player.insertInQueue(songs, at: index)
        }
    }
}

/// Hero card for the current track: large artwork, metadata, a scrubber with
/// elapsed/total times and a prominent transport cluster — the panel's
/// centerpiece.
private struct CurrentTrackCard: View {
    @Environment(PlayerModel.self) private var player
    let song: Song
    /// In-progress scrub position; seek once on release (see docs/03).
    @State private var scrubValue: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero artwork, full-bleed: flush with the panel edges and the
            // toolbar above, filling all available width.
            HeroArtwork(coverArt: song.coverArt)

            VStack(alignment: .leading, spacing: 0) {
                // Title / artist / album.
                Text(song.title)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Text(song.artist ?? "—")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 3)
                if let album = song.album, !album.isEmpty {
                    Text(album)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .padding(.top, 1)
                }

                // Scrubber + times.
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
                .accessibilityLabel("Playback position")
                .padding(.top, 12)

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
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 14)
        }
    }

    /// Shuffle · prev / play / next · repeat — larger than the toolbar cluster,
    /// with the play button as the one prominent (accent-filled) control and
    /// shuffle/repeat as subordinate toggles (accent when active), Music-style.
    private var transport: some View {
        HStack(spacing: 20) {
            Button { player.shuffle.toggle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .foregroundStyle(player.shuffle ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Shuffle")

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Previous")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .accentColor.opacity(0.45), radius: 6, y: 3)
                    .contentShape(Circle())
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Next")

            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .foregroundStyle(player.repeatMode != .off ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Repeat")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }
}

/// Full-bleed square artwork: fills the panel's width edge-to-edge, so no
/// corner rounding, border or shadow.
private struct HeroArtwork: View {
    let coverArt: String?

    var body: some View {
        GeometryReader { geo in
            ArtworkView(coverArt: coverArt, size: geo.size.width, cornerRadius: 0)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A queued track with a soft rounded hover highlight. Hovering reveals a
/// play button over the artwork and swaps the duration for a remove button —
/// buttons only, so the row body stays free for drag-to-reorder.
private struct QueueRow: View {
    let song: Song
    var onPlay: () -> Void
    var onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                ArtworkView(coverArt: song.coverArt, size: 36, cornerRadius: 6)
                    .overlay {
                        if hovering {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.black.opacity(0.45))
                            Image(systemName: "play.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("Play")
            .accessibilityLabel("Play \(song.title)")

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.body.weight(.medium)).lineLimit(1)
                Text(song.artist ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove")
            } else {
                Text(formatTime(song.duration))
                    .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
    }
}

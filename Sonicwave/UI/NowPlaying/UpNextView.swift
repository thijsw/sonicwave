import SwiftUI

/// The Now Playing / Up Next panel: a prominent current-track card plus the
/// upcoming queue with drag-to-reorder, hover-to-remove, and play-from-here.
/// Shown as an inspector. See docs/04-ui-ux.md.
struct UpNextView: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Group {
            if player.currentTrack == nil && player.upNext.isEmpty {
                ContentUnavailableView("Not Playing", systemImage: "music.note",
                                       description: Text("Tracks you play appear here."))
            } else {
                List {
                    if let current = player.currentTrack {
                        Section {
                            NowPlayingCard(song: current)
                        } header: {
                            Text("Now Playing")
                        }
                    }

                    Section {
                        if player.upNext.isEmpty {
                            Text("Nothing up next")
                                .foregroundStyle(.secondary).font(.callout)
                        } else {
                            ForEach(Array(player.queue.enumerated()), id: \.element.id) { pair in
                                if pair.offset > (player.currentIndex ?? -1) {
                                    QueueRow(song: pair.element) { player.removeFromQueue(at: pair.offset) }
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) { player.playFromQueue(at: pair.offset) }
                                        .contextMenu {
                                            Button("Play") { player.playFromQueue(at: pair.offset) }
                                            Button("Remove", role: .destructive) {
                                                player.removeFromQueue(at: pair.offset)
                                            }
                                        }
                                }
                            }
                            .onMove { offsets, destination in
                                player.moveQueue(from: offsets, to: destination)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Up Next")
                            Spacer()
                            if !player.upNext.isEmpty {
                                Button("Clear") { player.clearUpNext() }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .help("Clear Up Next")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Up Next")
    }
}

/// Prominent card for the currently playing track.
private struct NowPlayingCard: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(coverArt: song.coverArt, size: 56, cornerRadius: 6)
                .shadow(radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.headline).lineLimit(2)
                Text(song.artist ?? "—").font(.subheadline)
                    .foregroundStyle(.secondary).lineLimit(1)
                if let album = song.album, !album.isEmpty {
                    Text(album).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.tint).font(.caption)
        }
        .padding(.vertical, 4)
    }
}

/// A queued track. Shows its duration, or a remove button on hover.
private struct QueueRow: View {
    let song: Song
    var onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(coverArt: song.coverArt, size: 34, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).lineLimit(1)
                Text(song.artist ?? "—").font(.caption)
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
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .onHover { hovering = $0 }
    }
}

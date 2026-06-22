import SwiftUI

/// The Up Next / play queue panel: the current track plus upcoming tracks, with
/// drag-to-reorder, remove, and play-from-here. Shown as an inspector.
/// See docs/04-ui-ux.md.
struct UpNextView: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        List {
            if let current = player.currentTrack {
                Section("Now Playing") {
                    QueueRow(song: current, isCurrent: true)
                }
            }

            Section("Up Next") {
                if player.upNext.isEmpty {
                    Text("Nothing queued")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { pair in
                        if pair.offset > (player.currentIndex ?? -1) {
                            QueueRow(song: pair.element, isCurrent: false)
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
            }
        }
        .listStyle(.inset)
        .navigationTitle("Up Next")
        .toolbar {
            if !player.upNext.isEmpty {
                ToolbarItem {
                    Button("Clear", systemImage: "trash") { player.clearUpNext() }
                        .help("Clear Up Next")
                }
            }
        }
    }
}

private struct QueueRow: View {
    let song: Song
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(coverArt: song.coverArt, size: 36, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).lineLimit(1)
                    .fontWeight(isCurrent ? .semibold : .regular)
                Text(song.artist ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .font(.caption)
            } else {
                Text(formatTime(song.duration))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

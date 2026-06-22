import SwiftUI

/// A dense, sortable track table — the core iTunes-style list used by Songs,
/// album/playlist/genre detail, and favorites. Double-click (or ⏎) plays the
/// row and sets the queue from the supplied list. See docs/04-ui-ux.md.
struct TrackTableView: View {
    let tracks: [Song]
    @Environment(PlayerModel.self) private var player

    @State private var sortOrder = [KeyPathComparator(\Song.title)]
    @State private var selection = Set<Song.ID>()

    private var sortedTracks: [Song] {
        tracks.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedTracks, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("#") { song in
                Text(song.track.map(String.init) ?? "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(36)

            TableColumn("Title", value: \.title) { song in
                Text(song.title).lineLimit(1)
            }

            TableColumn("Artist", value: \.artistSort) { song in
                Text(song.artist ?? "—").lineLimit(1).foregroundStyle(.secondary)
            }

            TableColumn("Album", value: \.albumSort) { song in
                Text(song.album ?? "—").lineLimit(1).foregroundStyle(.secondary)
            }

            TableColumn("Genre", value: \.genreSort) { song in
                Text(song.genre ?? "—").lineLimit(1).foregroundStyle(.secondary)
            }

            TableColumn("Time", value: \.durationSort) { song in
                Text(formatTime(song.duration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(56)
        }
        .contextMenu(forSelectionType: Song.ID.self) { ids in
            Button("Play") { playSelection(ids) }
            Button("Play Next") { player.playNext(songs(for: ids)) }
            Button("Add to Up Next") { player.enqueue(songs(for: ids)) }
        } primaryAction: { ids in
            playSelection(ids)
        }
    }

    private func songs(for ids: Set<Song.ID>) -> [Song] {
        sortedTracks.filter { ids.contains($0.id) }
    }

    private func playSelection(_ ids: Set<Song.ID>) {
        let ordered = sortedTracks
        guard let first = ids.first, let index = ordered.firstIndex(where: { $0.id == first }) else {
            player.play(tracks: ordered, startAt: 0)
            return
        }
        player.play(tracks: ordered, startAt: index)
    }
}

func formatTime(_ seconds: Int?) -> String {
    guard let seconds, seconds > 0 else { return "—" }
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}

func formatTime(_ seconds: TimeInterval) -> String {
    formatTime(Int(seconds.rounded()))
}

/// Sort-friendly accessors that avoid optionals in comparators.
extension Song {
    var artistSort: String { artist ?? "" }
    var albumSort: String { album ?? "" }
    var genreSort: String { genre ?? "" }
    var durationSort: Int { duration ?? 0 }
}

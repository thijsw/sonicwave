import SwiftUI

/// A dedicated album screen (pushed onto the navigation stack): a header with
/// artwork, title, artist, year + play/shuffle/favorite, then the track list
/// rendered with the shared `TrackTableView`. Mirrors `PlaylistDetailView`.
struct AlbumDetailView: View {
    let album: Album
    @Environment(LibraryModel.self) private var library
    @Environment(PlayerModel.self) private var player
    @State private var tracks: [Song] = []
    @State private var starredOverride: Bool?

    // Derive from the library's starred set (source of truth) so the state
    // persists across revisits; the optimistic override gives instant feedback.
    private var isStarred: Bool {
        starredOverride ?? (album.isStarred || library.starredAlbums.contains { $0.id == album.id })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TrackTableView(tracks: tracks, columns: [.title, .artist, .genre, .time])
        }
        .navigationTitle(album.name)
        .task(id: album.id) {
            tracks = await library.songs(forAlbum: album.id)
            await library.loadStarredIfNeeded()
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ArtworkView(coverArt: album.coverArt, size: 96, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(album.name).font(.title2).bold()
                Text(album.artist ?? "—").foregroundStyle(.secondary)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button {
                        player.play(tracks: tracks)
                    } label: { Label("Play", systemImage: "play.fill") }
                    .disabled(tracks.isEmpty)

                    Button {
                        player.play(tracks: tracks.shuffled())
                    } label: { Label("Shuffle", systemImage: "shuffle") }
                    .disabled(tracks.isEmpty)

                    Button {
                        let new = !isStarred
                        starredOverride = new
                        Task { await library.setAlbumStarred(new, albumId: album.id) }
                    } label: {
                        Image(systemName: isStarred ? "star.fill" : "star")
                            .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isStarred ? "Remove from Favorites" : "Add to Favorites")
                    .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding()
    }

    private var subtitle: String {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        let count = tracks.count
        parts.append("\(count) song\(count == 1 ? "" : "s")")
        let total = tracks.reduce(0) { $0 + ($1.duration ?? 0) }
        if total > 0 { parts.append(formatTime(total)) }
        return parts.joined(separator: " · ")
    }
}

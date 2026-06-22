import SwiftUI

/// An album's track list with a header (artwork, title, artist, play button).
struct AlbumDetailView: View {
    let album: Album
    @Environment(LibraryModel.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Song] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ArtworkView(coverArt: album.coverArt, size: 120, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(album.name).font(.title2).bold()
                    Text(album.artist ?? "—").font(.title3).foregroundStyle(.secondary)
                    if let year = album.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button {
                        player.play(tracks: tracks)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(tracks.isEmpty)
                }
                Spacer()
            }
            .padding()

            Divider()

            TrackTableView(tracks: tracks)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            tracks = await library.songs(forAlbum: album.id)
        }
    }
}

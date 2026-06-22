import SwiftUI

/// A server playlist's tracks. Full create/edit/delete/reorder arrives in M5
/// (docs/04-ui-ux.md); this view currently lists and plays the playlist.
struct PlaylistDetailView: View {
    let playlistID: String
    @Environment(LibraryModel.self) private var library
    @Environment(PlayerModel.self) private var player
    @State private var playlist: Playlist?

    var body: some View {
        Group {
            if let playlist {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(playlist.name).font(.title2).bold()
                            if let count = playlist.songCount {
                                Text("\(count) songs").foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            player.play(tracks: playlist.entry ?? [])
                        } label: { Label("Play", systemImage: "play.fill") }
                        .disabled(playlist.entry?.isEmpty ?? true)
                    }
                    .padding()
                    Divider()
                    TrackTableView(tracks: playlist.entry ?? [])
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .task(id: playlistID) {
            playlist = await library.playlist(id: playlistID)
        }
    }
}

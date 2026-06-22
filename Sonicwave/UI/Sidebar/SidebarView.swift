import SwiftUI

/// The iTunes-style sidebar: a Library section and a Playlists section.
/// See docs/04-ui-ux.md.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Environment(LibraryModel.self) private var library

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Albums", systemImage: "square.stack").tag(SidebarSelection.albums)
                Label("Artists", systemImage: "music.mic").tag(SidebarSelection.artists)
                Label("Songs", systemImage: "music.note.list").tag(SidebarSelection.songs)
                Label("Genres", systemImage: "guitars").tag(SidebarSelection.genres)
                Label("Favorites", systemImage: "star").tag(SidebarSelection.favorites)
            }

            Section("Playlists") {
                if library.playlists.isEmpty {
                    Text("No playlists")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(library.playlists) { playlist in
                        Label(playlist.name, systemImage: "music.note.list")
                            .tag(SidebarSelection.playlist(id: playlist.id))
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        .task {
            await library.loadPlaylistsIfNeeded()
        }
    }
}

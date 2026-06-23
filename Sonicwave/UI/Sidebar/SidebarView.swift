import SwiftUI

/// The iTunes-style sidebar: a Library section and a Playlists section with
/// create / rename / delete. See docs/04-ui-ux.md.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Environment(LibraryModel.self) private var library

    @State private var showNewPlaylist = false
    @State private var newName = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""
    @State private var deleting: Playlist?
    @State private var dropTargetID: String?

    /// The asset red, loaded by name so it stays red even though the sidebar is
    /// tinted gray (iTunes shows colored icons over a neutral-gray selection).
    private let iconColor = Color("AccentColor")

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                libraryItem("Albums", "square.stack", .albums)
                libraryItem("Artists", "music.mic", .artists)
                libraryItem("Songs", "music.note.list", .songs)
                libraryItem("Genres", "guitars", .genres)
                libraryItem("Favorites", "star", .favorites)
            }

            Section {
                if library.playlists.isEmpty {
                    Text("No playlists")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(library.playlists) { playlist in
                        playlistRow(playlist)
                    }
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button {
                        newName = ""
                        showNewPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Playlist")
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        .task {
            await library.loadPlaylistsIfNeeded()
        }
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    if let created = await library.createPlaylist(name: name) {
                        selection = .playlist(id: created.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Playlist", isPresented: renamingBinding, presenting: renaming) { playlist in
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let id = playlist.id
                Task { await library.renamePlaylist(id: id, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Playlist", isPresented: deletingBinding, presenting: deleting) { playlist in
            Button("Delete", role: .destructive) {
                let id = playlist.id
                Task { await library.deletePlaylist(id: id) }
                if selection == .playlist(id: id) { selection = .albums }
            }
            Button("Cancel", role: .cancel) {}
        } message: { playlist in
            Text("Delete “\(playlist.name)”? This cannot be undone.")
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        Label(playlist.name, systemImage: "music.note.list")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(SidebarSelection.playlist(id: playlist.id))
            .listRowBackground(dropTargetID == playlist.id
                ? RoundedRectangle(cornerRadius: 6).fill(iconColor.opacity(0.25))
                : nil)
            .dropDestination(for: DraggedTrack.self) { items, _ in
                let ids = items.map(\.songId)
                guard !ids.isEmpty else { return false }
                let pid = playlist.id
                Task { await library.addToPlaylist(id: pid, songIds: ids) }
                return true
            } isTargeted: { targeted in
                if targeted {
                    dropTargetID = playlist.id
                } else if dropTargetID == playlist.id {
                    dropTargetID = nil
                }
            }
            .contextMenu {
                Button("Rename…") {
                    renameText = playlist.name
                    renaming = playlist
                }
                Button("Delete", role: .destructive) { deleting = playlist }
            }
    }

    @ViewBuilder
    private func libraryItem(_ title: String, _ symbol: String, _ tag: SidebarSelection) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(iconColor)
        }
        .tag(tag)
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

import SwiftUI

/// Grid of album artwork with infinite-scroll pagination. Selecting an album
/// opens its track list. See docs/04-ui-ux.md.
struct AlbumsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(spacing: 0) {
            // Sort lives in the view's own header now that the window toolbar is
            // replaced by the custom now-playing bar.
            HStack {
                Spacer()
                sortMenu
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            ScrollView {
                AlignedAdaptiveGrid(tileMinimum: 160, spacing: 20) {
                    ForEach(library.albums) { album in
                        Button { navigator.openAlbum(album) } label: {
                            AlbumGridCell(coverArt: album.coverArt,
                                          title: album.name,
                                          subtitle: album.artist ?? "—")
                        }
                        .buttonStyle(.plain)
                        .task {
                            if album.id == library.albums.last?.id {
                                await library.loadMoreAlbums()
                            }
                        }
                    }
                }
                .padding(20)

                if case .loading = library.albumsState {
                    ProgressView().padding()
                }
            }
        }
        .navigationTitle("Albums")
        .task { await library.loadAlbumsIfNeeded() }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: Binding(
                get: { library.albumSortType },
                set: { type in Task { await library.changeAlbumSort(to: type) } }
            )) {
                Text("Recently Added").tag("newest")
                Text("Recently Played").tag("recent")
                Text("Most Played").tag("frequent")
                Text("Title").tag("alphabeticalByName")
                Text("Artist").tag("alphabeticalByArtist")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort Albums")
    }
}

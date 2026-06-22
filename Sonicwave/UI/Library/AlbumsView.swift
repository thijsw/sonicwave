import SwiftUI

/// Grid of album artwork with infinite-scroll pagination. Selecting an album
/// opens its track list. See docs/04-ui-ux.md.
struct AlbumsView: View {
    @Environment(LibraryModel.self) private var library
    @State private var selected: Album?

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(library.albums) { album in
                    AlbumCell(album: album)
                        .onTapGesture { selected = album }
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
        .navigationTitle("Albums")
        .task { await library.loadAlbumsIfNeeded() }
        .sheet(item: $selected) { album in
            AlbumDetailView(album: album)
                .frame(minWidth: 560, minHeight: 480)
        }
    }
}

private struct AlbumCell: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(coverArt: album.coverArt, size: 170, cornerRadius: 8)
                .shadow(radius: 2, y: 1)
            Text(album.name).font(.callout).bold().lineLimit(1)
            Text(album.artist ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

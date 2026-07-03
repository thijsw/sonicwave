import SwiftUI

/// Starred albums (a shelf) and starred songs. Maps to getStarred2.
struct FavoritesView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator

    private var isEmpty: Bool {
        library.starredSongs.isEmpty && library.starredAlbums.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                ContentUnavailableView("No Favorites", systemImage: "star",
                                       description: Text("Songs and albums you star will appear here."))
            } else {
                VStack(spacing: 0) {
                    if !library.starredAlbums.isEmpty {
                        albumsShelf
                        Divider()
                    }
                    if !library.starredSongs.isEmpty {
                        TrackTableView(tracks: library.starredSongs,
                                       columns: [.title, .artist, .album, .genre, .time])
                    } else {
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Favorites")
        .task { await library.loadStarredIfNeeded() }
    }

    private var albumsShelf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Albums").font(.headline)
                .padding(.horizontal).padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(library.starredAlbums) { album in
                        Button { navigator.openAlbum(album) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ArtworkView(coverArt: album.coverArt, size: 110, cornerRadius: 6)
                                Text(album.name).font(.caption).lineLimit(1)
                                Text(album.artist ?? "—").font(.caption2)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 110, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal).padding(.bottom, 10)
            }
        }
    }
}

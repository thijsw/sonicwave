import SwiftUI

/// List of artists; selecting one shows their albums.
struct ArtistsView: View {
    @Environment(LibraryModel.self) private var library
    @State private var selected: Artist?

    var body: some View {
        List(library.artists, selection: Binding(
            get: { selected?.id },
            set: { id in selected = library.artists.first { $0.id == id } }
        )) { artist in
            HStack(spacing: 10) {
                ArtworkView(coverArt: artist.coverArt, size: 36, cornerRadius: 18)
                Text(artist.name)
                Spacer()
                if let count = artist.albumCount {
                    Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .tag(artist.id)
        }
        .navigationTitle("Artists")
        .task { await library.loadArtistsIfNeeded() }
        .sheet(item: $selected) { artist in
            ArtistDetailView(artist: artist)
                .frame(minWidth: 560, minHeight: 480)
        }
    }
}

private struct ArtistDetailView: View {
    let artist: Artist
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [Album] = []
    @State private var selectedAlbum: Album?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(albums) { album in
                    VStack(alignment: .leading, spacing: 6) {
                        ArtworkView(coverArt: album.coverArt, size: 150, cornerRadius: 8)
                        Text(album.name).font(.callout).lineLimit(1)
                        if let year = album.year {
                            Text(String(year)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onTapGesture { selectedAlbum = album }
                }
            }
            .padding()
        }
        .navigationTitle(artist.name)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { albums = await library.albums(forArtist: artist.id) }
        .sheet(item: $selectedAlbum) { album in
            AlbumDetailView(album: album).frame(minWidth: 560, minHeight: 480)
        }
    }
}

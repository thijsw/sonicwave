import SwiftUI

/// List of artists; selecting one pushes a dedicated artist view with their
/// albums. See docs/04-ui-ux.md.
struct ArtistsView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        List(library.artists) { artist in
            NavigationLink(value: artist) {
                HStack(spacing: 10) {
                    ArtworkView(coverArt: artist.coverArt, size: 36, cornerRadius: 18)
                    Text(artist.name)
                    Spacer()
                    if let count = artist.albumCount {
                        Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Artists")
        .task { await library.loadArtistsIfNeeded() }
    }
}

/// An artist's albums as a grid; selecting one pushes its album view. Pushed
/// onto the navigation stack from `ArtistsView`.
struct ArtistDetailView: View {
    let artist: Artist
    @Environment(LibraryModel.self) private var library
    @State private var albums: [Album] = []

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(albums) { album in
                    NavigationLink(value: album) {
                        VStack(alignment: .leading, spacing: 6) {
                            ArtworkView(coverArt: album.coverArt, size: 150, cornerRadius: 8)
                            Text(album.name).font(.callout).lineLimit(1)
                            if let year = album.year {
                                Text(String(year)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(artist.name)
        .task(id: artist.id) { albums = await library.albums(forArtist: artist.id) }
    }
}

import SwiftUI

/// Artists as a master-detail split (no push navigation): the artist list on
/// the left, the selected artist's albums on the right. Search hands an artist
/// off via `Navigator.pendingArtist`. See docs/04-ui-ux.md.
struct ArtistsView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @State private var selectedID: Artist.ID?

    private var selected: Artist? {
        library.artists.first { $0.id == selectedID } ?? library.artists.first
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(library.artists) { artist in
                    HStack(spacing: 10) {
                        ArtworkView(coverArt: artist.coverArt, size: 36, cornerRadius: 18)
                        Text(artist.name).lineLimit(1)
                        Spacer()
                        if let count = artist.albumCount {
                            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .tag(artist.id)
                }
            }
            .listStyle(.plain)
            .frame(width: 240)

            Divider()

            if let artist = selected {
                ArtistDetailView(artist: artist)
            } else {
                ContentUnavailableView("No Artists", systemImage: "music.mic")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await library.loadArtistsIfNeeded()
            if selectedID == nil { selectedID = library.artists.first?.id }
        }
        // Consume an artist handed off from search results.
        .task(id: navigator.pendingArtist) {
            if let artist = navigator.pendingArtist {
                selectedID = artist.id
                navigator.pendingArtist = nil
            }
        }
    }
}

/// The selected artist's albums as a grid; selecting one opens the album
/// in place (via `Navigator`).
struct ArtistDetailView: View {
    let artist: Artist
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator
    @State private var albums: [Album] = []

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(artist.name).font(.title2).bold()
                    .padding(.horizontal).padding(.top, 14)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums) { album in
                        Button { navigator.openAlbum(album) } label: {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: artist.id) { albums = await library.albums(forArtist: artist.id) }
    }
}

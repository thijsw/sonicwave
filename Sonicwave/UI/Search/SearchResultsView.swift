import SwiftUI

/// Global search results: artist and album shelves (tappable, pushing the same
/// detail screens as the library) above the shared striped track table used
/// everywhere else — double-click-to-play, context menu, favorites and the
/// now-playing indicator included. Debounced and cancellation-aware via
/// `.task(id:)`. See docs/04-ui-ux.md.
struct SearchResultsView: View {
    let query: String
    @Environment(LibraryModel.self) private var library
    @State private var results = LibraryModel.SearchResults()
    @State private var isSearching = false

    var body: some View {
        Group {
            if results.isEmpty {
                if isSearching {
                    ProgressView()
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                VStack(spacing: 0) {
                    if !results.artists.isEmpty {
                        artistsShelf
                        Divider()
                    }
                    if !results.albums.isEmpty {
                        albumsShelf
                        Divider()
                    }
                    if !results.songs.isEmpty {
                        TrackTableView(tracks: results.songs,
                                       columns: [.title, .artist, .album, .time])
                    } else {
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Search")
        .task(id: query) {
            isSearching = true
            // Light debounce so typing doesn't fire a request per keystroke.
            // Existing results stay visible while the next search runs, so the
            // page doesn't flash a spinner on every keystroke.
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            results = await library.search(query)
            isSearching = false
        }
    }

    /// Matching artists as a shelf of circular portraits; selecting one pushes
    /// the artist's albums (same destination as the Artists section).
    private var artistsShelf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Artists").font(.headline)
                .padding(.horizontal).padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(results.artists) { artist in
                        NavigationLink(value: artist) {
                            VStack(spacing: 6) {
                                ArtworkView(coverArt: artist.coverArt, size: 64, cornerRadius: 32)
                                Text(artist.name).font(.caption).lineLimit(1)
                            }
                            .frame(width: 90)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal).padding(.bottom, 10)
            }
        }
    }

    /// Matching albums as a cover shelf, identical to the Favorites shelf;
    /// selecting one pushes the album's track list.
    private var albumsShelf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Albums").font(.headline)
                .padding(.horizontal).padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(results.albums) { album in
                        NavigationLink(value: album) {
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

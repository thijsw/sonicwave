import SwiftUI

/// Global search results grouped into Artists / Albums / Songs. Debounced and
/// cancellation-aware via `.task(id:)`. See docs/04-ui-ux.md.
struct SearchResultsView: View {
    let query: String
    @Environment(LibraryModel.self) private var library
    @Environment(PlayerModel.self) private var player
    @State private var results = LibraryModel.SearchResults()
    @State private var isSearching = false

    var body: some View {
        Group {
            if isSearching {
                ProgressView()
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    if !results.artists.isEmpty {
                        Section("Artists") {
                            ForEach(results.artists) { artist in
                                Label(artist.name, systemImage: "music.mic")
                            }
                        }
                    }
                    if !results.albums.isEmpty {
                        Section("Albums") {
                            ForEach(results.albums) { album in
                                HStack {
                                    ArtworkView(coverArt: album.coverArt, size: 28, cornerRadius: 4)
                                    Text(album.name)
                                    Text(album.artist ?? "").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !results.songs.isEmpty {
                        Section("Songs") {
                            ForEach(results.songs) { song in
                                Button {
                                    player.play(tracks: results.songs,
                                                startAt: results.songs.firstIndex(of: song) ?? 0)
                                } label: {
                                    HStack {
                                        Text(song.title)
                                        Spacer()
                                        Text(song.artist ?? "").foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
        .task(id: query) {
            isSearching = true
            // Light debounce so typing doesn't fire a request per keystroke.
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            results = await library.search(query)
            isSearching = false
        }
    }
}

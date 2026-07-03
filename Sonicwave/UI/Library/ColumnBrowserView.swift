import SwiftUI

/// iTunes-style column browser: Genre → Artist → Album panes above a filtered
/// track table. Selecting in a pane narrows the panes to its right and the
/// tracks below. See docs/04-ui-ux.md.
struct ColumnBrowserView: View {
    @Environment(LibraryModel.self) private var library

    @State private var songs: [Song] = []          // songs for the selected genre
    @State private var selectedGenre: String?
    @State private var selectedArtist: String?
    @State private var selectedAlbum: String?
    @State private var isLoading = false

    /// With no genre selected, browse the all-songs sample; otherwise the genre's
    /// songs. (Subsonic has no "all songs" endpoint, so the base is a sample.)
    private var baseSongs: [Song] {
        selectedGenre == nil ? library.songs : songs
    }

    private var artists: [String] {
        uniqueSorted(baseSongs.compactMap(\.artist))
    }

    private var albums: [String] {
        let scoped = selectedArtist == nil ? baseSongs : baseSongs.filter { $0.artist == selectedArtist }
        return uniqueSorted(scoped.compactMap(\.album))
    }

    private var filteredTracks: [Song] {
        baseSongs.filter { song in
            (selectedArtist == nil || song.artist == selectedArtist)
                && (selectedAlbum == nil || song.album == selectedAlbum)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                pane(title: "Genre",
                     items: library.genres.map(\.value),
                     selection: $selectedGenre,
                     allLabel: "All Genres")
                Divider()
                pane(title: "Artist",
                     items: artists,
                     selection: $selectedArtist,
                     allLabel: "All Artists")
                Divider()
                pane(title: "Album",
                     items: albums,
                     selection: $selectedAlbum,
                     allLabel: "All Albums")
            }
            .frame(height: 200)

            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTableView(tracks: filteredTracks,
                               columns: [.title, .artist, .album, .genre, .quality, .time])
            }
        }
        .task {
            await library.loadSongsIfNeeded()
            await library.loadGenresIfNeeded()
        }
        .onChange(of: selectedGenre) { _, genre in
            selectedArtist = nil
            selectedAlbum = nil
            Task { await loadGenre(genre) }
        }
        .onChange(of: selectedArtist) { selectedAlbum = nil }
    }

    @ViewBuilder
    private func pane(title: String, items: [String],
                      selection: Binding<String?>, allLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Styled to match the track table's header row below (same type,
            // height and hairline), so the browser reads as one table system.
            Text(title)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24, alignment: .leading)
            Divider()
            // Separator-free rows: the track table below draws no row rules,
            // so the panes shouldn't either.
            List(selection: selection) {
                Text(allLabel).tag(String?.none)
                    .listRowSeparator(.hidden)
                ForEach(items, id: \.self) { item in
                    Text(item).tag(String?.some(item))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadGenre(_ genre: String?) async {
        guard let genre else { songs = []; return }
        isLoading = true
        songs = await library.songs(forGenre: genre)
        isLoading = false
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

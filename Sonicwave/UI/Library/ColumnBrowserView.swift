import SwiftUI

/// iTunes-style column browser: Genre → Artist → Album panes above a filtered
/// track table. Selecting in a pane narrows the panes to its right and the
/// tracks below. See docs/04-ui-ux.md.
struct ColumnBrowserView: View {
    @Environment(LibraryModel.self) private var library

    @State private var songs: [Song] = []          // songs for the selected genre
    @State private var isLoading = false

    // Pane selections persist across launches ("" = nothing selected). The
    // cascade (genre resets artist+album, artist resets album) lives in the
    // binding setters so restore doesn't re-trigger it.
    @AppStorage("browser.genre") private var storedGenre = ""
    @AppStorage("browser.artist") private var storedArtist = ""
    @AppStorage("browser.album") private var storedAlbum = ""

    private var selectedGenre: String? { storedGenre.isEmpty ? nil : storedGenre }
    private var selectedArtist: String? { storedArtist.isEmpty ? nil : storedArtist }
    private var selectedAlbum: String? { storedAlbum.isEmpty ? nil : storedAlbum }

    private var genreSelection: Binding<String?> {
        Binding(
            get: { selectedGenre },
            set: { genre in
                storedGenre = genre ?? ""
                storedArtist = ""
                storedAlbum = ""
                Task { await loadGenre(genre) }
            })
    }

    private var artistSelection: Binding<String?> {
        Binding(
            get: { selectedArtist },
            set: { artist in
                storedArtist = artist ?? ""
                storedAlbum = ""
            })
    }

    private var albumSelection: Binding<String?> {
        Binding(get: { selectedAlbum }, set: { storedAlbum = $0 ?? "" })
    }

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
                     selection: genreSelection,
                     allLabel: "All Genres")
                Divider()
                pane(title: "Artist",
                     items: artists,
                     selection: artistSelection,
                     allLabel: "All Artists")
                Divider()
                pane(title: "Album",
                     items: albums,
                     selection: albumSelection,
                     allLabel: "All Albums")
            }
            .frame(height: 200)

            Divider()

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTableView(tracks: filteredTracks,
                               columns: [.title, .artist, .album, .genre, .quality, .time],
                               sortAutosaveKey: "browser",
                               scrollAutosaveKey: "browser")
            }
        }
        .task {
            await library.loadSongsIfNeeded()
            await library.loadGenresIfNeeded()
            // Restore: a persisted genre needs its songs loaded (without the
            // cascade — the restored artist/album selections must survive).
            if selectedGenre != nil, songs.isEmpty {
                await loadGenre(selectedGenre)
            }
        }
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
        let fetched = await library.songs(forGenre: genre)
        // The Binding-setter Task isn't cancelled by a newer selection —
        // two rapid genre clicks race, and the slower fetch must never land
        // under the newer selection.
        guard storedGenre == genre else { return }
        songs = fetched
        isLoading = false
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

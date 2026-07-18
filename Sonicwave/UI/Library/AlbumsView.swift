import SwiftUI

/// Grid of album artwork with infinite-scroll pagination. Selecting an album
/// opens its track list. See docs/04-ui-ux.md.
struct AlbumsView: View {
    @Environment(AppModel.self) private var app
    @Environment(LibraryModel.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        VStack(spacing: 0) {
            // Sort lives in the view's own header now that the window toolbar is
            // replaced by the custom now-playing bar.
            HStack {
                Spacer()
                Button { app.shuffleAlbums() } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .disabled(app.isPreparingMix)
                .help("Play random albums in full (uses the active filter)")
                filterMenu
                sortMenu
                    // Genre/year are list *types* server-side, so an active
                    // filter owns the ordering.
                    .disabled(library.albumFilter != .none)
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
        .task {
            await library.loadAlbumsIfNeeded()
            await library.loadGenresIfNeeded()   // feeds the filter menu
        }
    }

    private var filterMenu: some View {
        Menu {
            Button("All Albums") {
                Task { await library.changeAlbumFilter(to: .none) }
            }
            Picker("Genre", selection: filterBinding) {
                ForEach(library.genres) { genre in
                    Text(genre.value).tag(LibraryModel.AlbumFilter.genre(genre.value))
                }
            }
            .pickerStyle(.menu)
            Picker("Decade", selection: filterBinding) {
                ForEach(Array(stride(from: 2020, through: 1950, by: -10)), id: \.self) { decade in
                    Text(verbatim: "\(decade)s")
                        .tag(LibraryModel.AlbumFilter.years(from: decade, through: decade + 9))
                }
            }
            .pickerStyle(.menu)
        } label: {
            Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter Albums")
    }

    private var filterBinding: Binding<LibraryModel.AlbumFilter> {
        Binding(
            get: { library.albumFilter },
            set: { filter in Task { await library.changeAlbumFilter(to: filter) } }
        )
    }

    private var filterLabel: String {
        switch library.albumFilter {
        case .none: return "Filter"
        case let .genre(name): return name
        case let .years(from, _): return "\(from)s"
        }
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

import SwiftUI

/// The main window shell: a NavigationSplitView with the iTunes-style sidebar,
/// a content detail area, and a persistent now-playing bar pinned to the
/// bottom. See docs/04-ui-ux.md.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(ConnectionModel.self) private var connection
    @Environment(LibraryModel.self) private var library

    @State private var selection: SidebarSelection? = .albums
    @State private var searchText = ""
    @AppStorage("showUpNext") private var showUpNext = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem {
                        Button {
                            showUpNext.toggle()
                        } label: {
                            Label("Up Next", systemImage: "list.bullet.rectangle")
                        }
                        .help("Show Up Next")
                    }
                }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .inspector(isPresented: $showUpNext) {
            UpNextView()
                .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NowPlayingBar()
        }
        .overlay {
            if !isConnected { notConnectedOverlay }
        }
        .task {
            await connection.refresh()
        }
    }

    private var isConnected: Bool {
        if case .connected = connection.state { return true }
        return connection.isConfigured
    }

    @ViewBuilder
    private var detail: some View {
        if !searchText.isEmpty {
            SearchResultsView(query: searchText)
        } else {
            switch selection {
            case .albums: AlbumsView()
            case .artists: ArtistsView()
            case .songs: SongsView()
            case .genres: GenresView()
            case .favorites: FavoritesView()
            case let .playlist(id): PlaylistDetailView(playlistID: id)
            case nil: ContentUnavailableView("Select an item", systemImage: "music.note")
            }
        }
    }

    private var notConnectedOverlay: some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text("Connect to your OpenSubsonic server to browse your library.")
        } actions: {
            Button("Open Settings…") { openSettings() }
                .buttonStyle(.borderedProminent)
        }
        .background(.background)
    }
}

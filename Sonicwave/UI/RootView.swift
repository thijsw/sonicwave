import SwiftUI

/// The main window shell: a NavigationSplitView with the iTunes-style sidebar,
/// a content detail area, and a persistent now-playing bar pinned to the
/// bottom. See docs/04-ui-ux.md.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(ConnectionModel.self) private var connection
    @Environment(LibraryModel.self) private var library
    @Environment(PlayerModel.self) private var player

    // Persisted across launches so the app reopens on the last-used section.
    // @AppStorage (not @SceneStorage) so it restores regardless of the system's
    // window-restoration setting; the app is effectively single-window.
    @AppStorage("sidebarSelection") private var selectionRaw = SidebarSelection.albums.rawValue
    @State private var searchText = ""
    /// Programmatic focus for the sidebar search field (⌘F).
    @State private var searchPresented = false
    /// In-place navigation (opened album, artist hand-off) — no NavigationStack.
    @State private var navigator = Navigator()
    @AppStorage("showUpNext") private var showUpNext = false
    @Environment(\.openSettings) private var openSettings

    private var selection: SidebarSelection? { SidebarSelection(rawValue: selectionRaw) }

    var body: some View {
        // The now-playing experience lives in the window's real unified toolbar
        // (see SonicwaveApp's window/toolbar style): transport leading, the
        // now-playing display centered, volume + panel toggle trailing; search
        // sits in the sidebar. Using the native toolbar — rather than a custom
        // bar drawn above the split view — means window dragging, traffic
        // lights, resize and full-screen are all handled by the system.
        NavigationSplitView {
            SidebarView(selection: Binding(
                get: { selection },
                set: { selectionRaw = ($0 ?? .albums).rawValue }
            ))
        } detail: {
            // The pinned hairline is the toolbar's bottom border — and it
            // keeps scrollable content from extending up under the (fully
            // transparent) toolbar: scroll views only underlap a safe-area
            // edge they sit flush against, and without a NavigationStack
            // there's no scroll-edge material to blur what pokes through.
            VStack(spacing: 0) {
                Divider()
                detail
            }
        }
        .toolbar {
            // NOTE: SwiftUI on macOS cannot host custom toolbar items in the
            // strip above the sidebar (attaching them to the sidebar column
            // breaks the toolbar layout; .automatic there even drops the whole
            // NSToolbar) — so the transport leads the detail column, right
            // beside the sidebar divider, as close to the traffic lights as
            // the framework allows.
            // Breathing room at both toolbar ends nudges the transport and
            // volume clusters toward the center.
            ToolbarItem(placement: .navigation) {
                TransportControls()
                    .padding(.leading, 16)
            }
            ToolbarItem(placement: .principal) {
                NowPlayingDisplay()
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    VolumeControl()
                    Button { showUpNext.toggle() } label: {
                        Label("Now Playing", systemImage: "list.bullet.rectangle")
                    }
                    .help(showUpNext ? "Hide Now Playing" : "Show Now Playing")
                    .disabled(!nowPlayingAvailable)
                }
                .padding(.trailing, 16)
            }
        }
        // In the sidebar (Music-style): a fixed, always-expanded field that
        // can't collapse into an icon or hop between columns the way the
        // toolbar placement did when the inspector squeezed the detail area.
        .searchable(text: $searchText, isPresented: $searchPresented,
                    placement: .sidebar, prompt: "Search")
        // ⌘F focuses the search field — a hidden shortcut button, since
        // .searchable has no command-level focus hook.
        .background {
            Button("") { searchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        // The panel only presents while it has something to show; the stored
        // preference survives, so it reappears when playback starts again.
        .inspector(isPresented: Binding(
            get: { showUpNext && nowPlayingAvailable },
            set: { showUpNext = $0 }
        )) {
            NowPlayingPanel()
                .inspectorColumnWidth(min: 300, ideal: 344, max: 420)
        }
        .overlay {
            if !isConnected { notConnectedOverlay }
        }
        .environment(navigator)
        // Switching sections or editing the query leaves the opened album.
        .onChange(of: selectionRaw) { navigator.album = nil }
        .onChange(of: searchText) { navigator.album = nil }
        // Search hands an artist off to the Artists section.
        .onChange(of: navigator.pendingArtist) { _, artist in
            if artist != nil {
                selectionRaw = SidebarSelection.artists.rawValue
                searchText = ""
            }
        }
        .task {
            await connection.refresh()
        }
        // Drive section loading here rather than from each detail view's own
        // `.task`: the detail root view didn't reliably run its `.task` on
        // initial launch, which left the first screen blank.
        .task(id: selectionRaw) {
            await load(selection)
        }
    }

    private func load(_ selection: SidebarSelection?) async {
        switch selection {
        case .albums: await library.loadAlbumsIfNeeded()
        case .artists: await library.loadArtistsIfNeeded()
        case .songs: await library.loadSongsIfNeeded()
        case .favorites: await library.loadStarredIfNeeded()
        case .playlist, nil: break
        }
    }

    private var isConnected: Bool {
        if case .connected = connection.state { return true }
        return connection.isConfigured
    }

    /// The Now Playing panel is only relevant while something is playing or
    /// queued.
    private var nowPlayingAvailable: Bool {
        player.currentTrack != nil || !player.upNext.isEmpty
    }

    @ViewBuilder
    private var detail: some View {
        // An opened album renders in place of the current section (with its
        // own inline Back link); search results sit under that.
        if let album = navigator.album {
            AlbumDetailView(album: album)
        } else if !searchText.isEmpty {
            SearchResultsView(query: searchText)
        } else {
            switch selection {
            case .albums: AlbumsView()
            case .artists: ArtistsView()
            case .songs: SongsView()
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

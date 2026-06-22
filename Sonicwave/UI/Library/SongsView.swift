import SwiftUI

/// Flat songs table. Subsonic has no "all songs" endpoint, so this currently
/// shows a random sample (see docs/05-data-and-caching.md, known limitation).
struct SongsView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Group {
            if library.songs.isEmpty, case .loading = library.songsState {
                ProgressView()
            } else {
                TrackTableView(tracks: library.songs)
            }
        }
        .navigationTitle("Songs")
        .task { await library.loadSongsIfNeeded() }
    }
}

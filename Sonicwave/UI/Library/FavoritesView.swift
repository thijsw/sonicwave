import SwiftUI

/// Starred songs (and, in a header, starred albums). Maps to getStarred2.
struct FavoritesView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Group {
            if library.starredSongs.isEmpty {
                ContentUnavailableView("No Favorites", systemImage: "star",
                                       description: Text("Songs you star will appear here."))
            } else {
                TrackTableView(tracks: library.starredSongs)
            }
        }
        .navigationTitle("Favorites")
        .task { await library.loadStarredIfNeeded() }
    }
}

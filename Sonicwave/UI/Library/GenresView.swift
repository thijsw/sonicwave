import SwiftUI

/// Genre list; selecting a genre shows its songs.
struct GenresView: View {
    @Environment(LibraryModel.self) private var library
    @State private var selected: Genre?

    var body: some View {
        List(library.genres, selection: Binding(
            get: { selected?.id },
            set: { id in selected = library.genres.first { $0.id == id } }
        )) { genre in
            HStack {
                Text(genre.value)
                Spacer()
                if let count = genre.songCount {
                    Text("\(count) songs").foregroundStyle(.secondary).font(.callout)
                }
            }
            .tag(genre.id)
        }
        .navigationTitle("Genres")
        .task { await library.loadGenresIfNeeded() }
        .sheet(item: $selected) { genre in
            GenreDetailView(genre: genre).frame(minWidth: 640, minHeight: 480)
        }
    }
}

private struct GenreDetailView: View {
    let genre: Genre
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Song] = []

    var body: some View {
        TrackTableView(tracks: tracks)
            .navigationTitle(genre.value)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { tracks = await library.songs(forGenre: genre.value) }
    }
}

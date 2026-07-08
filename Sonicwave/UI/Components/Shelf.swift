import SwiftUI

/// A titled horizontal scroller of tappable tiles — the shelf rows on the
/// Favorites and Search screens.
struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
                .padding(.horizontal).padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) { content }
                    .padding(.horizontal).padding(.bottom, 10)
            }
        }
    }
}

/// Album-cover shelf; selecting a cover pushes the album's track list.
struct AlbumShelf: View {
    let albums: [Album]
    @Environment(Navigator.self) private var navigator

    var body: some View {
        Shelf(title: "Albums") {
            ForEach(albums) { album in
                Button { navigator.openAlbum(album) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ArtworkView(coverArt: album.coverArt, size: 110, cornerRadius: 8)
                        Text(album.name).font(.caption).lineLimit(1)
                        Text(album.artist ?? "—").font(.caption2)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: 110, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

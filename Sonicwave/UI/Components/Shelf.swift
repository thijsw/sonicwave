import SwiftUI

/// A titled horizontal scroller of tappable tiles — the shelf rows on the
/// Home, Favorites and Search screens. `accessory` sits at the header's
/// trailing edge (e.g. Home's re-roll button).
struct Shelf<Content: View>: View {
    let title: String
    var accessory: AnyView?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                accessory
            }
            .padding(.horizontal).padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) { content }
                    .padding(.horizontal).padding(.bottom, 10)
            }
        }
    }
}

/// Album-cover shelf; selecting a cover pushes the album's track list.
/// `tileSize` lets a page vary shelf prominence (Home's featured row runs
/// larger than the standard 110pt).
struct AlbumShelf: View {
    var title = "Albums"
    let albums: [Album]
    var tileSize: CGFloat = 110
    var accessory: AnyView?
    @Environment(Navigator.self) private var navigator

    var body: some View {
        Shelf(title: title, accessory: accessory) {
            ForEach(albums) { album in
                Button { navigator.openAlbum(album) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ArtworkView(coverArt: album.coverArt, size: tileSize, cornerRadius: 8)
                        Text(album.name).font(.caption).lineLimit(1)
                        Text(album.artist ?? "—").font(.caption2)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: tileSize, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

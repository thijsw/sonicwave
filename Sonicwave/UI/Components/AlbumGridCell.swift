import SwiftUI

/// Album cell for adaptive grids: a square cover that fills the grid cell's
/// width, with title + subtitle beneath. Sizing the cover to the cell (rather
/// than a fixed size) keeps covers flush with each other and the page inset —
/// a fixed-size cover in a stretched adaptive cell floats toward the center by
/// a title-length-dependent amount.
struct AlbumGridCell: View {
    let coverArt: String?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ArtworkView(coverArt: coverArt, size: geo.size.width, cornerRadius: 8)
            }
            .aspectRatio(1, contentMode: .fit)
            .shadow(radius: 2, y: 1)
            Text(title).font(.callout).bold().lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

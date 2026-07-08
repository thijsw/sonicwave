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

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Covers lift slightly on hover (the design's cue that they're
            // clickable), with a deeper shadow selling the elevation.
            GeometryReader { geo in
                ArtworkView(coverArt: coverArt, size: geo.size.width, cornerRadius: 8)
            }
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(hovering ? 0.45 : 0.25),
                    radius: hovering ? 9 : 2, y: hovering ? 6 : 1)
            .offset(y: hovering ? -3 : 0)
            .animation(.easeOut(duration: 0.15), value: hovering)
            // Title and artist read as one tight block under the cover.
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).bold().lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

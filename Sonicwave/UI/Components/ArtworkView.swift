import SwiftUI

/// Async, cached cover-art view with a placeholder. Requests a server-resized
/// image at roughly the displayed point size × screen scale.
/// See docs/05-data-and-caching.md.
struct ArtworkView: View {
    let coverArt: String?
    var size: CGFloat
    var cornerRadius: CGFloat = 6
    /// SF Symbol shown while there is no artwork (branding surfaces pass the
    /// app icon's waveform).
    var placeholderSymbol: String = "music.note"

    @State private var image: NSImage?

    init(coverArt: String?, size: CGFloat, cornerRadius: CGFloat = 6,
         placeholderSymbol: String = "music.note") {
        self.coverArt = coverArt
        self.size = size
        self.cornerRadius = cornerRadius
        self.placeholderSymbol = placeholderSymbol
        // Seed from any already-cached variant so cached art shows immediately
        // (no placeholder flash when the same art is shown at a different size).
        _image = State(initialValue: ArtworkCache.shared.cachedVariant(coverArt: coverArt))
    }

    /// Requested pixel size: displayed points × screen scale, rounded up to a
    /// 160px quantum so live resizes (the geometry-sized hero) reuse a handful
    /// of cache entries instead of fetching one variant per pixel.
    private var fetchPixels: Int {
        max(Int((size * 2 / 160).rounded(.up)) * 160, 160)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .overlay {
                        // Scaled with the view so the glyph reads at hero
                        // sizes too (fixed imageScale vanished at 200pt+).
                        Image(systemName: placeholderSymbol)
                            .font(.system(size: max(12, size * 0.22)))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Keyed on the fetch size as well as the id: views measured by
        // GeometryReader (the Now Playing hero) first render at a placeholder
        // size, and the fetch must re-run once the real width is known.
        .task(id: "\(coverArt ?? "")-\(fetchPixels)") {
            // Show a cached variant for this id at once, then upgrade to the
            // fetched size (keep the variant if the fetch fails).
            image = ArtworkCache.shared.cachedVariant(coverArt: coverArt)
            if let exact = await ArtworkCache.shared.image(coverArt: coverArt, size: fetchPixels) {
                image = exact
            }
        }
    }
}

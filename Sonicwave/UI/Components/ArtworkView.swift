import SwiftUI

/// Async, cached cover-art view with a placeholder. Requests a server-resized
/// image at roughly the displayed point size × screen scale.
/// See docs/05-data-and-caching.md.
struct ArtworkView: View {
    let coverArt: String?
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    @State private var image: NSImage?

    init(coverArt: String?, size: CGFloat, cornerRadius: CGFloat = 6) {
        self.coverArt = coverArt
        self.size = size
        self.cornerRadius = cornerRadius
        // Seed from any already-cached variant so cached art shows immediately
        // (no placeholder flash when the same art is shown at a different size).
        _image = State(initialValue: ArtworkCache.shared.cachedVariant(coverArt: coverArt))
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
                        Image(systemName: "music.note")
                            .imageScale(.medium)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: coverArt) {
            // Show a cached variant for this id at once, then upgrade to the
            // exact size (keep the variant if the exact fetch fails).
            image = ArtworkCache.shared.cachedVariant(coverArt: coverArt)
            let pixels = Int(size * 2)
            if let exact = await ArtworkCache.shared.image(coverArt: coverArt, size: pixels) {
                image = exact
            }
        }
    }
}

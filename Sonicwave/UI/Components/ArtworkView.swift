import SwiftUI

/// Async, cached cover-art view with a placeholder. Requests a server-resized
/// image at roughly the displayed point size × screen scale.
/// See docs/05-data-and-caching.md.
struct ArtworkView: View {
    let coverArt: String?
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    @State private var image: NSImage?

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
            let pixels = Int(size * 2)
            image = await ArtworkCache.shared.image(coverArt: coverArt, size: pixels)
        }
    }
}

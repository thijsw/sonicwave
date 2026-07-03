import SwiftUI

/// In-place navigation state — the app deliberately has no NavigationStack
/// (no push/pop, no toolbar back chrome). An opened album renders as a detail
/// over the current section with its own inline Back link, and search can hand
/// an artist off to the Artists section. See docs/04-ui-ux.md.
@MainActor
@Observable
final class Navigator {
    /// Album shown as an in-place detail over the current section (nil = none).
    var album: Album?
    /// Artist the Artists section should select next (handed off from search).
    var pendingArtist: Artist?

    func openAlbum(_ album: Album) { self.album = album }
    func closeAlbum() { album = nil }
    func openArtist(_ artist: Artist) { pendingArtist = artist }
}

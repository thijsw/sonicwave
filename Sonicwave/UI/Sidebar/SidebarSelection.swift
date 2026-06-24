import Foundation

/// Sidebar selection, grouped iTunes-style into Library and Playlists.
/// See docs/04-ui-ux.md.
enum SidebarSelection: Hashable {
    case albums
    case artists
    case songs
    case favorites
    case playlist(id: String)
}

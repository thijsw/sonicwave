import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Drag payload for a track row. Carries the song id (so it can be *added* to a
/// playlist when dropped on the sidebar) plus its source row index (so it can be
/// *reordered* when dropped within its own playlist — unambiguous even when the
/// same song appears twice). Encoded as JSON, a system-registered type, so the
/// in-app drag-and-drop matches reliably.
struct DraggedTrack: Codable, Transferable, Sendable {
    let songId: String
    let index: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

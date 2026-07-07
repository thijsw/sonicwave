import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// NSTableView subclass that surfaces a per-row context menu and Return-to-play.
private final class InnerTableView: NSTableView {
    var contextMenuProvider: ((IndexSet) -> NSMenu?)?
    var onReturn: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return contextMenuProvider?(selectedRowIndexes)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            onReturn?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// A selectable data column in the track list. The now-playing indicator and
/// favorite-star columns are always present (fixed-width affordances); these are
/// the content columns each call site opts into explicitly.
enum TrackColumn {
    case title, artist, album, genre, quality, time

    struct Widths {
        let initial: CGFloat
        let min: CGFloat
        let max: CGFloat
    }

    var id: String {
        switch self {
        case .title: "title"
        case .artist: "artist"
        case .album: "album"
        case .genre: "genre"
        case .quality: "quality"
        case .time: "time"
        }
    }
    var header: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .genre: "Genre"
        case .quality: "Quality"
        case .time: "Time"
        }
    }
    var widths: Widths {
        switch self {
        case .title: Widths(initial: 240, min: 120, max: 10_000)
        case .artist: Widths(initial: 170, min: 80, max: 10_000)
        case .album: Widths(initial: 170, min: 80, max: 10_000)
        case .genre: Widths(initial: 100, min: 60, max: 400)
        case .quality: Widths(initial: 78, min: 64, max: 110)
        case .time: Widths(initial: 54, min: 54, max: 80)
        }
    }
    var alignRight: Bool { self == .time }
}

/// AppKit `NSTableView`-backed track list — the single track view used across the
/// app — giving the Music behaviours SwiftUI can't combine: edge-to-edge
/// alternating stripes, **double-click-to-play**, reliable multi-selection,
/// click-to-sort headers, drag-to-playlist, a now-playing **speaker** column,
/// and a favorite column. See docs/04-ui-ux.md.
struct MusicTrackTable: NSViewRepresentable {
    var tracks: [Song]
    var sortable: Bool = true
    /// When set, the sort key/direction persist to UserDefaults under this
    /// name and are restored on creation (one slot per view kind).
    var sortAutosaveKey: String?
    /// Content columns to show, in order. Caller decides explicitly.
    var columns: [TrackColumn]
    var nowPlayingID: String?
    @Binding var selection: Set<Int>          // indices into the *displayed* order
    var isFavorite: (Song) -> Bool
    var onPlay: ([Song], Int) -> Void          // displayed order + start index
    var onPlayNext: (Song) -> Void             // ⌥-double-click: queue as next
    var onToggleFavorite: (Song) -> Void
    var makeMenu: ([Song], IndexSet) -> NSMenu?  // displayed order + selected indices

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = InnerTableView()
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked)
        table.contextMenuProvider = { context.coordinator.parent.makeMenu(context.coordinator.displayed, $0) }
        table.onReturn = { context.coordinator.playSelected() }
        table.setDraggingSourceOperationMask([.copy], forLocal: true)

        func addColumn(_ id: String, _ title: String, width: CGFloat, min: CGFloat, max: CGFloat,
                       sortKey: String? = nil, alignRight: Bool = false) {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = min
            col.maxWidth = max
            // Match the header's alignment to the cell content (e.g. right-aligned Time).
            (col.headerCell as? NSTableHeaderCell)?.alignment = alignRight ? .right : .left
            if sortable, let sortKey {
                col.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
            }
            table.addTableColumn(col)
        }
        addColumn("indicator", "", width: 22, min: 22, max: 22)
        for column in columns {
            let widths = column.widths
            addColumn(column.id, column.header, width: widths.initial, min: widths.min, max: widths.max,
                      sortKey: column.id, alignRight: column.alignRight)
        }
        addColumn("fav", "", width: 26, min: 26, max: 26)
        // Flexible columns absorb extra width so rows/stripes fill edge-to-edge.
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        // Restore a persisted sort — only for a column that still exists.
        if sortable, let descriptor = context.coordinator.persistedSortDescriptor(),
           table.tableColumns.contains(where: { $0.identifier.rawValue == descriptor.key }) {
            context.coordinator.restoringSort = true
            table.sortDescriptors = [descriptor]
            context.coordinator.restoringSort = false
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        context.coordinator.table = table
        context.coordinator.rebuild()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = scroll.documentView as? InnerTableView else { return }
        table.contextMenuProvider = { context.coordinator.parent.makeMenu(context.coordinator.displayed, $0) }
        context.coordinator.reloadIfNeeded()

        let want = IndexSet(selection.filter { context.coordinator.displayed.indices.contains($0) })
        if table.selectedRowIndexes != want {
            context.coordinator.updatingSelection = true
            table.selectRowIndexes(want, byExtendingSelection: false)
            context.coordinator.updatingSelection = false
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: MusicTrackTable
        weak var table: NSTableView?
        var updatingSelection = false
        /// Set while makeNSView applies the persisted sort, so the delegate
        /// callback doesn't clear the selection binding mid view-update.
        var restoringSort = false
        private(set) var displayed: [Song] = []
        private var sortKey: String?
        private var ascending = true
        private var signature: [String] = []

        init(_ parent: MusicTrackTable) { self.parent = parent }

        /// Recompute the displayed (optionally sorted) order and reload.
        func rebuild() {
            displayed = sortedTracks()
            table?.reloadData()
        }

        func reloadIfNeeded() {
            var sig = parent.tracks.map(\.id)
            sig.append("sort:\(sortKey ?? "")\(ascending)")
            sig.append("np:\(parent.nowPlayingID ?? "")")
            sig.append(contentsOf: parent.tracks.map { parent.isFavorite($0) ? "1" : "0" })
            guard sig != signature else { return }
            signature = sig
            rebuild()
        }

        private func sortedTracks() -> [Song] {
            guard let key = sortKey else { return parent.tracks }
            let asc = ascending
            func text(_ lhs: String?, _ rhs: String?) -> Bool {
                (lhs ?? "").localizedCaseInsensitiveCompare(rhs ?? "") == .orderedAscending
            }
            return parent.tracks.sorted { lhs, rhs in
                let result: Bool
                switch key {
                case "artist": result = text(lhs.artist, rhs.artist)
                case "album": result = text(lhs.album, rhs.album)
                case "genre": result = text(lhs.displayGenre, rhs.displayGenre)
                case "quality": result = lhs.qualityRank < rhs.qualityRank
                case "time": result = (lhs.duration ?? 0) < (rhs.duration ?? 0)
                default: result = text(lhs.title, rhs.title)
                }
                return asc ? result : !result
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            TrackRowView()
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            if let descriptor = tableView.sortDescriptors.first {
                sortKey = descriptor.key
                ascending = descriptor.ascending
            } else {
                sortKey = nil
            }
            persistSort(key: sortKey, ascending: ascending)
            signature = [] // force rebuild
            reloadIfNeeded()
            guard !restoringSort else { return }
            parent.selection = []
            tableView.deselectAll(nil)
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard displayed.indices.contains(row),
                  let data = try? JSONEncoder().encode(DraggedTrack(songId: displayed[row].id,
                                                                    index: row,
                                                                    song: displayed[row]))
            else { return nil }
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.json.identifier))
            return item
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let id = tableColumn?.identifier.rawValue, displayed.indices.contains(row) else { return nil }
            let song = displayed[row]

            switch id {
            case "indicator":
                return indicatorCell(for: song)
            case "quality":
                guard let label = song.qualityLabel else { return NSTableCellView() }
                return QualityBadgeCell(text: label)
            case "fav":
                return favoriteCell(for: song, row: row)
            default:
                return textCell(id: id, song: song)
            }
        }

        @MainActor private func indicatorCell(for song: Song) -> NSTableCellView {
            let cell = NSTableCellView()
            if song.id == parent.nowPlayingID {
                let icon = NSImageView()
                icon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Now playing")
                icon.contentTintColor = NSColor(named: "AccentColor")
                icon.imageScaling = .scaleProportionallyDown
                icon.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(icon)
                NSLayoutConstraint.activate([
                    icon.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 13),
                    icon.heightAnchor.constraint(equalToConstant: 13)
                ])
            }
            return cell
        }

        @MainActor private func favoriteCell(for song: Song, row: Int) -> NSTableCellView {
            let cell = NSTableCellView()
            let btn = NSButton()
            btn.isBordered = false
            btn.imagePosition = .imageOnly
            btn.image = NSImage(systemSymbolName: parent.isFavorite(song) ? "star.fill" : "star",
                                accessibilityDescription: "Favorite")
            btn.contentTintColor = parent.isFavorite(song) ? .systemYellow : .tertiaryLabelColor
            btn.tag = row
            btn.target = self
            btn.action = #selector(favoriteClicked(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                btn.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        @MainActor private func textCell(id: String, song: Song) -> NSTableCellView {
            let text: String
            switch id {
            case "title": text = song.title
            case "artist": text = song.artist ?? "—"
            case "album": text = song.album ?? "—"
            case "genre": text = song.displayGenre ?? "—"
            case "time": text = formatTime(song.duration)
            default: text = ""
            }
            let label = NSTextField(labelWithString: text)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            // Title is the primary label; other columns are dimmed. Assigning
            // `cell.textField` lets both turn white on the selected row.
            let cell: NSTableCellView = (id == "title") ? NSTableCellView() : SecondaryTextCell()
            if id != "title" { label.textColor = .secondaryLabelColor }
            cell.textField = label
            if id == "time" {
                label.alignment = .right
                label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            }
            cell.addSubview(label)
            let trailing = (id == "time") ? -6.0 : -4.0
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: trailing),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updatingSelection, let table else { return }
            parent.selection = Set(table.selectedRowIndexes)
        }

        @objc func doubleClicked() {
            guard let table, displayed.indices.contains(table.clickedRow) else { return }
            // ⌥-double-click queues the track next instead of playing it.
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                parent.onPlayNext(displayed[table.clickedRow])
            } else {
                parent.onPlay(displayed, table.clickedRow)
            }
        }

        @objc func favoriteClicked(_ sender: NSButton) {
            guard displayed.indices.contains(sender.tag) else { return }
            parent.onToggleFavorite(displayed[sender.tag])
        }

        func playSelected() {
            if let row = table?.selectedRowIndexes.min() { parent.onPlay(displayed, row) }
        }
    }
}

// MARK: - Sort persistence

extension MusicTrackTable.Coordinator {
    private var sortDefaultsKey: String? {
        parent.sortAutosaveKey.map { "trackSort.\($0)" }
    }

    func persistedSortDescriptor() -> NSSortDescriptor? {
        guard let key = sortDefaultsKey,
              let stored = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = stored.split(separator: "|")
        guard parts.count == 2 else { return nil }
        return NSSortDescriptor(key: String(parts[0]), ascending: parts[1] == "asc")
    }

    func persistSort(key sortKey: String?, ascending: Bool) {
        guard let key = sortDefaultsKey else { return }
        if let sortKey {
            UserDefaults.standard.set("\(sortKey)|\(ascending ? "asc" : "desc")", forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

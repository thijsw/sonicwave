import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// NSTableView subclass that surfaces a per-row context menu and Return-to-play.
private final class InnerTableView: NSTableView {
    var contextMenuProvider: ((IndexSet) -> NSMenu?)?
    var onReturn: (() -> Void)?
    /// Disc headers are not selectable; programmatic selection must skip them
    /// (`selectRowIndexes` bypasses the shouldSelect delegate).
    var selectableRow: ((Int) -> Bool)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0, selectableRow?(row) != false else { return nil }
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

/// Table rows: tracks interleaved with unselectable disc group headers.
/// All external index semantics (selection binding, onPlay, drag) stay in
/// *displayed*-track space; the coordinator's delegate methods translate.
enum TrackTableRow: Equatable {
    case header(String)
    case track(Int)   // index into the displayed track order

    static func build(tracks: [Song], headers: [Int: String]?) -> [TrackTableRow] {
        let plain = tracks.indices.map(TrackTableRow.track)
        guard let headers else { return plain }
        let discs = Set(tracks.map { $0.discNumber ?? 1 })
        guard discs.count > 1 else { return plain }
        var rows: [TrackTableRow] = []
        var current: Int?
        for (index, track) in tracks.enumerated() {
            let disc = track.discNumber ?? 1
            if disc != current {
                current = disc
                let title = headers[disc].map { "Disc \(disc) · \($0)" } ?? "Disc \(disc)"
                rows.append(.header(title))
            }
            rows.append(.track(index))
        }
        return rows
    }
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
    /// When set, the scroll offset persists under this name and is restored
    /// once the first rows arrive. Only for views whose content is stable
    /// across launches (Songs/Favorites/browser) — content-specific views
    /// (album detail, search) would restore a stranger's offset.
    var scrollAutosaveKey: String?
    /// Content columns to show, in order. Caller decides explicitly.
    var columns: [TrackColumn]
    /// Disc → subtitle; non-nil opts into disc group headers on multi-disc
    /// content (album page). Headers appear only in disc order — the natural
    /// order or an ascending # sort — since other sorts interleave discs.
    var discHeaders: [Int: String]?
    /// Order-stable rendering of `discHeaders` for the reload signature.
    var discHeadersSignature: String? {
        discHeaders.map { headers in
            headers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
        }
    }
    var nowPlayingID: String?
    @Binding var selection: Set<Int>          // indices into the *displayed* order
    var isFavorite: (Song) -> Bool
    var onPlay: ([Song], Int) -> Void          // displayed order + start index
    var onPlayNext: (Song) -> Void             // ⌥-double-click: queue as next
    var onToggleFavorite: (Song) -> Void
    var makeMenu: ([Song], IndexSet) -> NSMenu?  // displayed order + selected indices

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // @MainActor matches reality (AppKit calls the delegate/datasource and
    // action selectors on the main thread) and lets the compiler verify the
    // AppKit calls inside.
    @MainActor
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
        // Scroll persistence (see TrackTablePersistence.swift). The
        // selector-based observer is auto-unregistered on dealloc.
        var scrollRestored = false
        var pendingScrollSave: DispatchWorkItem?

        private(set) var rows: [TrackTableRow] = []

        init(_ parent: MusicTrackTable) { self.parent = parent }

        /// Recompute the displayed (optionally sorted) order and reload.
        func rebuild() {
            displayed = sortedTracks()
            rows = TrackTableRow.build(tracks: displayed, headers: activeDiscHeaders)
            table?.reloadData()
        }

        func reloadIfNeeded() {
            var sig = parent.tracks.map(\.id)
            sig.append("sort:\(sortKey ?? "")\(ascending)")
            sig.append("np:\(parent.nowPlayingID ?? "")")
            sig.append("discs:" + (parent.discHeadersSignature ?? "off"))
            sig.append(contentsOf: parent.tracks.map { parent.isFavorite($0) ? "1" : "0" })
            guard sig != signature else { return }
            signature = sig
            rebuild()
        }

        /// Headers require disc order: no user sort, or the disc-aware # sort
        /// ascending. Any other sort interleaves discs — headers withdraw.
        private var activeDiscHeaders: [Int: String]? {
            guard let headers = parent.discHeaders else { return nil }
            switch sortKey {
            case nil: return headers
            case "number": return ascending ? headers : nil
            default: return nil
            }
        }

        /// The displayed-track index at a table row (nil for a disc header).
        func trackIndex(atRow row: Int) -> Int? {
            guard rows.indices.contains(row), case let .track(index) = rows[row] else { return nil }
            return index
        }

        func tableRows(forTrackIndices indices: Set<Int>) -> IndexSet {
            IndexSet(indices.compactMap { rows.firstIndex(of: .track($0)) })
        }

        func menuForSelection(_ selectedRows: IndexSet) -> NSMenu? {
            parent.makeMenu(displayed, IndexSet(selectedRows.compactMap { trackIndex(atRow: $0) }))
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
                case "number":  // disc-aware track order
                    result = (lhs.discNumber ?? 1, lhs.track ?? 0)
                        < (rhs.discNumber ?? 1, rhs.track ?? 0)
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

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            trackIndex(atRow: row) == nil ? NSTableRowView() : TrackRowView()
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            trackIndex(atRow: row) == nil
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            trackIndex(atRow: row) != nil
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
            guard let index = trackIndex(atRow: row),
                  let data = try? JSONEncoder().encode(DraggedTrack(songId: displayed[index].id,
                                                                    index: index,
                                                                    song: displayed[index]))
            else { return nil }
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.json.identifier))
            return item
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let index = trackIndex(atRow: row) else {
                // Group rows get a single full-width view (tableColumn is nil).
                if case let .header(title) = rows[row] { return discHeaderCell(title) }
                return nil
            }
            guard let id = tableColumn?.identifier.rawValue else { return nil }
            let song = displayed[index]

            switch id {
            case "indicator":
                return indicatorCell(for: song)
            case "number" where song.id == parent.nowPlayingID:
                // The # column doubles as the now-playing column (iTunes
                // style): the speaker replaces the track number.
                return indicatorCell(for: song)
            case "quality":
                guard let label = song.qualityLabel else { return NSTableCellView() }
                return QualityBadgeCell(text: label)
            case "fav":
                return favoriteCell(for: song, trackIndex: index)
            default:
                return textCell(id: id, song: song)
            }
        }

        @MainActor private func discHeaderCell(_ title: String) -> NSTableCellView {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSTableCellView()
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        @MainActor private func indicatorCell(for song: Song) -> NSTableCellView {
            song.id == parent.nowPlayingID ? NowPlayingIndicatorCell() : NSTableCellView()
        }

        @MainActor private func favoriteCell(for song: Song, trackIndex: Int) -> NSTableCellView {
            let cell = NSTableCellView()
            let btn = NSButton()
            btn.isBordered = false
            btn.imagePosition = .imageOnly
            btn.image = NSImage(systemSymbolName: parent.isFavorite(song) ? "star.fill" : "star",
                                accessibilityDescription: "Favorite")
            btn.setAccessibilityLabel(parent.isFavorite(song) ? "Remove from Favorites" : "Add to Favorites")
            btn.contentTintColor = parent.isFavorite(song) ? .systemYellow : .tertiaryLabelColor
            btn.tag = trackIndex
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
            case "number": text = song.track.map(String.init) ?? ""
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
            if id == "time" || id == "number" {
                // Numbers center under the # header (sharing the column with
                // the centered now-playing speaker); times stay right-aligned.
                label.alignment = (id == "number") ? .center : .right
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
            parent.selection = Set(table.selectedRowIndexes.compactMap { trackIndex(atRow: $0) })
        }

        @objc func doubleClicked() {
            guard let table, let index = trackIndex(atRow: table.clickedRow) else { return }
            // ⌥-double-click queues the track next instead of playing it.
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                parent.onPlayNext(displayed[index])
            } else {
                parent.onPlay(displayed, index)
            }
        }

        @objc func favoriteClicked(_ sender: NSButton) {
            guard displayed.indices.contains(sender.tag) else { return }
            parent.onToggleFavorite(displayed[sender.tag])
        }

        func playSelected() {
            guard let row = table?.selectedRowIndexes.min(),
                  let index = trackIndex(atRow: row) else { return }
            parent.onPlay(displayed, index)
        }
    }
}

// MARK: - View lifecycle

extension MusicTrackTable {
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
        table.contextMenuProvider = { context.coordinator.menuForSelection($0) }
        table.selectableRow = { context.coordinator.trackIndex(atRow: $0) != nil }
        table.onReturn = { context.coordinator.playSelected() }
        table.setDraggingSourceOperationMask([.copy], forLocal: true)
        addColumns(to: table)

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
        if scrollAutosaveKey != nil {
            context.coordinator.observeScroll(of: scroll)
        }
        return scroll
    }

    private func addColumns(to table: NSTableView) {
        func addColumn(_ id: String, _ title: String, width: CGFloat, min: CGFloat, max: CGFloat,
                       sortKey: String? = nil, alignment: NSTextAlignment = .left) {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = min
            col.maxWidth = max
            // Match the header's alignment to the cell content (e.g.
            // right-aligned Time, centered #).
            col.headerCell.alignment = alignment
            if sortable, let sortKey {
                col.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
            }
            table.addTableColumn(col)
        }
        // With a track-number column, the # cell itself hosts the speaker on
        // the playing row (iTunes style) — no separate indicator column.
        if !columns.contains(.number) {
            addColumn("indicator", "", width: 22, min: 22, max: 22)
        }
        for column in columns {
            let widths = column.widths
            addColumn(column.id, column.header, width: widths.initial, min: widths.min, max: widths.max,
                      sortKey: column.id, alignment: column.alignment)
        }
        addColumn("fav", "", width: 26, min: 26, max: 26)
        // Flexible columns absorb extra width so rows/stripes fill edge-to-edge.
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = scroll.documentView as? InnerTableView else { return }
        table.contextMenuProvider = { context.coordinator.menuForSelection($0) }
        context.coordinator.reloadIfNeeded()
        context.coordinator.restoreScrollIfReady(scroll)

        let want = context.coordinator.tableRows(
            forTrackIndices: selection.filter { context.coordinator.displayed.indices.contains($0) })
        if table.selectedRowIndexes != want {
            context.coordinator.updatingSelection = true
            table.selectRowIndexes(want, byExtendingSelection: false)
            context.coordinator.updatingSelection = false
        }
    }
}

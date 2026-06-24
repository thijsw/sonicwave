import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// An `NSMenuItem` that runs a Swift closure, so context menus can be built inline.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }
    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }
    @objc private func run() { handler() }
}

/// Row view that draws a full-width selection in the app's red accent (like
/// Music), rather than the system accent.
private final class TrackRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        (NSColor(named: "AccentColor") ?? .selectedContentBackgroundColor).setFill()
        bounds.fill()
    }
}

/// Cell for the dimmed secondary columns: `secondaryLabelColor` normally, white
/// on the selected (emphasized) row so it stays legible on the red highlight —
/// matching how the managed title cell behaves.
private final class SecondaryTextCell: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            textField?.textColor = backgroundStyle == .emphasized
                ? .alternateSelectedControlTextColor
                : .secondaryLabelColor
        }
    }
}

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
    case title, artist, album, genre, time

    var id: String {
        switch self {
        case .title: "title"; case .artist: "artist"; case .album: "album"
        case .genre: "genre"; case .time: "time"
        }
    }
    var header: String {
        switch self {
        case .title: "Title"; case .artist: "Artist"; case .album: "Album"
        case .genre: "Genre"; case .time: "Time"
        }
    }
    /// (default, min, max) widths.
    var widths: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .title: (240, 120, 10_000)
        case .artist: (170, 80, 10_000)
        case .album: (170, 80, 10_000)
        case .genre: (100, 60, 400)
        case .time: (54, 54, 80)
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
    /// Content columns to show, in order. Caller decides explicitly.
    var columns: [TrackColumn]
    var nowPlayingID: String?
    @Binding var selection: Set<Int>          // indices into the *displayed* order
    var isFavorite: (Song) -> Bool
    var onPlay: ([Song], Int) -> Void          // displayed order + start index
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
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            c.minWidth = min
            c.maxWidth = max
            // Match the header's alignment to the cell content (e.g. right-aligned Time).
            (c.headerCell as? NSTableHeaderCell)?.alignment = alignRight ? .right : .left
            if sortable, let sortKey {
                c.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
            }
            table.addTableColumn(c)
        }
        addColumn("indicator", "", width: 22, min: 22, max: 22)
        for column in columns {
            let (w, lo, hi) = column.widths
            addColumn(column.id, column.header, width: w, min: lo, max: hi,
                      sortKey: column.id, alignRight: column.alignRight)
        }
        addColumn("fav", "", width: 26, min: 26, max: 26)
        // Flexible columns absorb extra width so rows/stripes fill edge-to-edge.
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

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
            return parent.tracks.sorted { a, b in
                let result: Bool
                switch key {
                case "artist": result = (a.artist ?? "").localizedCaseInsensitiveCompare(b.artist ?? "") == .orderedAscending
                case "album": result = (a.album ?? "").localizedCaseInsensitiveCompare(b.album ?? "") == .orderedAscending
                case "genre": result = (a.displayGenre ?? "").localizedCaseInsensitiveCompare(b.displayGenre ?? "") == .orderedAscending
                case "time": result = (a.duration ?? 0) < (b.duration ?? 0)
                default: result = a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
                return asc ? result : !result
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { displayed.count }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            TrackRowView()
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            if let d = tableView.sortDescriptors.first {
                sortKey = d.key
                ascending = d.ascending
            } else {
                sortKey = nil
            }
            signature = [] // force rebuild
            reloadIfNeeded()
            parent.selection = []
            tableView.deselectAll(nil)
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard displayed.indices.contains(row),
                  let data = try? JSONEncoder().encode(DraggedTrack(songId: displayed[row].id, index: row))
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
                let cell = NSTableCellView()
                if song.id == parent.nowPlayingID {
                    let iv = NSImageView()
                    iv.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Now playing")
                    iv.contentTintColor = NSColor(named: "AccentColor")
                    iv.imageScaling = .scaleProportionallyDown
                    iv.translatesAutoresizingMaskIntoConstraints = false
                    cell.addSubview(iv)
                    NSLayoutConstraint.activate([
                        iv.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                        iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                        iv.widthAnchor.constraint(equalToConstant: 13),
                        iv.heightAnchor.constraint(equalToConstant: 13),
                    ])
                }
                return cell

            case "fav":
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
                    btn.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                return cell

            default:
                let text: String
                switch id {
                case "title": text = song.title
                case "artist": text = song.artist ?? "—"
                case "album": text = song.album ?? "—"
                case "genre": text = song.displayGenre ?? "—"
                case "time": text = formatTime(song.duration)
                default: text = ""
                }
                let tf = NSTextField(labelWithString: text)
                tf.lineBreakMode = .byTruncatingTail
                tf.translatesAutoresizingMaskIntoConstraints = false
                // Title is the primary label; other columns are dimmed. Assigning
                // `cell.textField` lets both turn white on the selected row.
                let cell: NSTableCellView = (id == "title") ? NSTableCellView() : SecondaryTextCell()
                if id != "title" { tf.textColor = .secondaryLabelColor }
                cell.textField = tf
                if id == "time" {
                    tf.alignment = .right
                    tf.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                }
                cell.addSubview(tf)
                let trailing = (id == "time") ? -6.0 : -4.0
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: trailing),
                    tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                return cell
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updatingSelection, let table else { return }
            parent.selection = Set(table.selectedRowIndexes)
        }

        @objc func doubleClicked() {
            guard let table, table.clickedRow >= 0 else { return }
            parent.onPlay(displayed, table.clickedRow)
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

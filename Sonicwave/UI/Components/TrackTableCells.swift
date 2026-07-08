import AppKit

// Supporting AppKit pieces for `MusicTrackTable`: the closure-driven menu item
// used by its context menus and the custom row/cell views that give the table
// its Music-style selection and secondary-text treatment.

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
final class TrackRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        (NSColor(named: "AccentColor") ?? .selectedContentBackgroundColor).setFill()
        bounds.fill()
    }
}

/// Cell for the dimmed secondary columns: `secondaryLabelColor` normally, white
/// on the selected (emphasized) row so it stays legible on the red highlight —
/// matching how the managed title cell behaves.
final class SecondaryTextCell: NSTableCellView {
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            textField?.textColor = backgroundStyle == .emphasized
                ? .alternateSelectedControlTextColor
                : .secondaryLabelColor
        }
    }
}

/// Cell for the Quality column: a small rounded-outline badge ("FLAC",
/// "320 kbps") — white on the selected (emphasized) row like the other cells.
final class QualityBadgeCell: NSTableCellView {
    private let badge = NSView()
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 3
        badge.layer?.borderWidth = 1
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        label.stringValue = text
        label.font = .systemFont(ofSize: 9.5, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: badge.topAnchor, constant: 1.5),
            label.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: -1.5)
        ])
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyColors() }
    }

    private func applyColors() {
        let emphasized = backgroundStyle == .emphasized
        label.textColor = emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        badge.layer?.borderColor = emphasized
            ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.6).cgColor
            : NSColor.tertiaryLabelColor.cgColor
    }
}

/// Now-playing speaker cell: accent-tinted normally, white on the selected
/// (emphasized) row — accent-on-accent would vanish into the red selection.
final class NowPlayingIndicatorCell: NSTableCellView {
    private let icon = NSImageView()

    init() {
        super.init(frame: .zero)
        icon.image = NSImage(systemSymbolName: "speaker.wave.2.fill",
                             accessibilityDescription: "Now playing")
        icon.contentTintColor = NSColor(named: "AccentColor")
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            icon.contentTintColor = backgroundStyle == .emphasized
                ? .alternateSelectedControlTextColor
                : NSColor(named: "AccentColor")
        }
    }
}

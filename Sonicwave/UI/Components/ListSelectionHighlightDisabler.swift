import AppKit
import SwiftUI

/// Turns off the system selection highlight on a `List`'s backing
/// `NSTableView` — selection state, keyboard navigation and accessibility
/// keep working; only the drawing is disabled, so rows can draw their own
/// selection via `listRowBackground`. (The system pill is blended with the
/// container's vibrancy material, muting the app accent — custom-drawn
/// selections are how Music matches its accent exactly.)
///
/// Attach with `.background(ListSelectionHighlightDisabler())` on the `List`.
struct ListSelectionHighlightDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Disabler() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Disabler: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Defer: the table isn't attached yet when the background lands.
            DispatchQueue.main.async { [weak self] in
                guard let self, let table = self.nearestTableView() else { return }
                table.selectionHighlightStyle = .none
            }
        }

        /// The background view is a sibling of the List's scroll view, so
        /// walk up the ancestors and search each subtree for the nearest
        /// table (stopping at the first hit keeps us inside this List rather
        /// than reaching another one across the window).
        private func nearestTableView() -> NSTableView? {
            var ancestor = superview
            var previous: NSView = self
            while let current = ancestor {
                for sibling in current.subviews where sibling !== previous {
                    if let table = findTable(in: sibling) { return table }
                }
                previous = current
                ancestor = current.superview
            }
            return nil
        }

        private func findTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for sub in view.subviews {
                if let table = findTable(in: sub) { return table }
            }
            return nil
        }
    }
}

import SwiftUI

/// A left-aligned adaptive grid. `GridItem.adaptive(minimum:maximum:)`
/// centers the whole row once tiles reach their maximum size with width left
/// over — the grid's leading inset then fluctuates with window width. This
/// computes an explicit column count from the measured width instead and uses
/// uncapped flexible tiles, so the row always fills exactly: flush leading
/// and trailing edges at every width, tile size in a controlled band
/// (`tileMinimum` up to roughly a column's worth more on narrow windows).
struct AlignedAdaptiveGrid<Content: View>: View {
    var tileMinimum: CGFloat
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var columnCount = 4

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing),
                                 count: columnCount),
                  spacing: spacing) {
            content()
        }
        // Marks the grid's children as scroll targets so an enclosing
        // ScrollView can track/restore position by id (Albums grid).
        .scrollTargetLayout()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            columnCount = max(2, Int((width + spacing) / (tileMinimum + spacing)))
        }
    }
}

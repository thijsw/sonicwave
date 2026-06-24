import SwiftUI

/// Application entry point. Defines the scenes (main window, Settings,
/// menu-bar Now Playing panel) and injects the shared observable models into
/// the SwiftUI environment so every window and the menu-bar panel observe the
/// same state. See docs/01-architecture.md and docs/04-ui-ux.md.
@main
struct SonicwaveApp: App {
    /// Single source of truth for the whole app, owned for the process lifetime.
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.player)
                .environment(app.library)
                .environment(app.connection)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { SonicwaveCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
                .environment(app.connection)
        }

        MenuBarExtra("Sonicwave", systemImage: "music.note") {
            MenuBarPanel()
                .environment(app)
                .environment(app.player)
        }
        .menuBarExtraStyle(.window)
    }
}

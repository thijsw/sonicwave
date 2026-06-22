import SwiftUI

/// Menu-bar commands and standard keyboard shortcuts. Playback controls are
/// reachable from the Controls menu, not buried behind buttons.
/// See docs/04-ui-ux.md.
struct SonicwaveCommands: Commands {
    let app: AppModel
    @AppStorage("showUpNext") private var showUpNext = false
    @AppStorage("showColumnBrowser") private var showColumnBrowser = true

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Toggle("Show Up Next", isOn: $showUpNext)
                .keyboardShortcut("u", modifiers: .command)
            Toggle("Show Column Browser", isOn: $showColumnBrowser)
                .keyboardShortcut("b", modifiers: [.command, .option])
            Divider()
        }

        CommandMenu("Controls") {
            Button(app.player.isPlaying ? "Pause" : "Play") {
                app.player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(app.player.currentTrack == nil)

            Button("Next") { app.player.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(app.player.currentTrack == nil)

            Button("Previous") { app.player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(app.player.currentTrack == nil)

            Divider()

            Picker("Repeat", selection: Binding(
                get: { app.player.repeatMode },
                set: { app.player.repeatMode = $0 }
            )) {
                Text("Off").tag(RepeatMode.off)
                Text("All").tag(RepeatMode.all)
                Text("One").tag(RepeatMode.one)
            }

            Toggle("Shuffle", isOn: Binding(
                get: { app.player.shuffle },
                set: { app.player.shuffle = $0 }
            ))
        }
    }
}

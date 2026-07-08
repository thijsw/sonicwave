import SwiftUI

/// Menu-bar commands and standard keyboard shortcuts. Playback controls are
/// reachable from the Controls menu, not buried behind buttons.
/// See docs/04-ui-ux.md.
struct SonicwaveCommands: Commands {
    let app: AppModel
    @AppStorage("showUpNext") private var showUpNext = false
    @AppStorage("showColumnBrowser") private var showColumnBrowser = true

    var body: some Commands {
        // ⌘N creates a playlist, like Music/iTunes (replaces New Window).
        CommandGroup(replacing: .newItem) {
            Button("New Playlist…") { app.requestNewPlaylist() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!app.connection.isConnected)

            Divider()

            // Kicks off a server-side rescan; progress feedback lives in
            // Settings → Connection (the scan runs asynchronously anyway).
            Button("Update Server Library") {
                Task { await app.connection.startLibraryScan() }
            }
            .disabled(!app.connection.isConnected)
        }

        CommandGroup(after: .sidebar) {
            // The set goes through withAnimation so ⌘U opens the panel as one
            // coordinated layout pass (same as the LCD/toolbar toggles).
            Toggle("Show Now Playing", isOn: Binding(
                get: { showUpNext },
                set: { newValue in withAnimation { showUpNext = newValue } }
            ))
                .keyboardShortcut("u", modifiers: .command)
                .disabled(app.player.currentTrack == nil && app.player.upNext.isEmpty)
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

            Button("Increase Volume") { app.player.volume = min(1, app.player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Decrease Volume") { app.player.volume = max(0, app.player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)

            Divider()

            Button(currentTrackStarred ? "Remove from Favorites" : "Add to Favorites") {
                guard let track = app.player.currentTrack else { return }
                Task {
                    // Make sure the starred list is loaded so the toggle is truthful.
                    await app.library.loadStarredIfNeeded()
                    let starred = app.library.starredSongs.contains { $0.id == track.id }
                    await app.library.setStarred(!starred, songIds: [track.id])
                }
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(app.player.currentTrack == nil || !app.connection.isConnected)

            Button("Show Album in Library") { app.requestShowCurrentAlbum() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(app.player.currentTrack?.albumId == nil)

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

    private var currentTrackStarred: Bool {
        guard let track = app.player.currentTrack else { return false }
        return app.library.starredSongs.contains { $0.id == track.id }
    }
}

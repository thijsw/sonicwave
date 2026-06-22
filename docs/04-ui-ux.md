# 04 — Interface & UX

Model the **interaction design** on iTunes 12.6.3's genuinely-good patterns;
render everything in **modern, fully native** SwiftUI that follows the HIG and
adopts Liquid Glass automatically on macOS 26. SF Symbols and system typography
throughout. (See `00` for the philosophy and `09` for the design-import
workflow.)

## Window & scene structure ✅

- **Main window** — `WindowGroup` containing a `NavigationSplitView` shell.
- **Settings** — a `Settings` scene (native Preferences window; ⌘,). See `02`
  for server/auth/transcoding contents.
- **MenuBarExtra** — Now Playing panel scene (below).
- Support multiple windows, resizing, full-screen, Stage Manager, and
  **state restoration** (windows reopen where left; selected sidebar item,
  sort, column-browser selection, and scroll position restored). See `06`.

## Layout ✅

```
┌──────────┬──────────────────────────────────────────────┐
│          │  [ Genre ][ Artist ][ Album ]  ← column browser│
│ Sidebar  ├──────────────────────────────────────────────┤
│ (Library │                                                │
│  /Play-  │   Track Table (dense, sortable)                │
│  lists)  │   Title │ Artist │ Album │ Genre │ Time │ ★    │
│          │                                                │
├──────────┴──────────────────────────────────────────────┤
│ Now-Playing header: artwork · title/artist · scrubber ·  │
│ transport · volume · Up Next toggle                      │
└──────────────────────────────────────────────────────────┘
```

A persistent now-playing header spans the bottom (iTunes-like). Up Next is a
toggleable panel/inspector on the trailing side.

## Sidebar (`NavigationSplitView`) ✅

Grouped like iTunes, using `Section`s and SF Symbols:

- **Library**
  - Albums · Artists · Songs · Genres · Favorites (starred)
- **Playlists**
  - The user's server playlists (live from `getPlaylists`), each selectable;
    context menu for rename/delete; "+" to create.

Selection drives the detail area. `LibraryModel`/`PlaylistsModel` back the
content; sidebar shows lightweight counts where cheap.

## Track table ✅

- SwiftUI **`Table`** with sortable columns: Title, Artist, Album, Genre, Time
  (duration), Track #, Year, ★ (starred toggle). Default + per-view column
  sets; user-adjustable sort (`TableColumnSort`).
- Dense row height; right-align numeric columns; monospaced-digit time.
- Double-click (or ⏎) plays the row and sets the queue from the current view;
  ⌥-double-click / context menu "Play Next" / "Add to Up Next".
- Context menu: Play, Play Next, Add to Up Next, Add to Playlist ▸, Star/Unstar,
  Go to Album/Artist, Get Info.
- Multi-select; drag selected rows to a playlist in the sidebar or into Up Next.
- Virtualized/lazy rows; paginate from `LibraryStore` (see `02`/`05`).

## Column browser ✅

Above the track table, a horizontal multi-pane browser filtering
**Genre → Artist → Album** (iTunes pattern). Selecting in a left pane narrows
the panes to its right and the track table below. Implemented as adjacent
selectable lists; selections are part of restorable view state. Toggleable
(View menu / shortcut) so users who prefer a plain table can hide it.

## Up Next / play queue ✅

- A panel listing the current queue with the now-playing row highlighted and
  upcoming/history sections.
- **Reorderable** by drag (`.onMove`), remove rows, "Play from here," clear
  upcoming. Edits mutate `PlayerModel.queue`; gapless pre-buffer target updates
  accordingly (see `03`).

## Now-playing header ✅

- Cached artwork thumbnail (see `05`), title + artist (click → navigate to
  album/artist), a **scrubber** bound to throttled position (drag to seek),
  elapsed/remaining labels, transport (prev/play-pause/next), repeat + shuffle
  toggles, volume slider, output-device menu, Up Next toggle.

## MenuBarExtra Now Playing panel ✅

- `MenuBarExtra` with **`.menuBarExtraStyle(.window)`** dropping a compact
  panel modeled on the modern macOS Music / Control Center Now Playing dropdown
  (this replaces the old iTunes MiniPlayer):
  - Large artwork, title/artist/album, scrubber, transport, volume,
    output-device quick-switch.
- Observes the same `PlayerModel` instance as the main window (shared via the
  environment) so it never drifts. Works while the main window is closed.

## Global search ✅

- A search field in the toolbar (`.searchable`) bound to `SearchModel`, calling
  `search3` with debounce + task cancellation (see `02`).
- Results grouped Artists / Albums / Songs; selecting navigates or plays.
- ⌘F focuses search.

## Menus & keyboard shortcuts ✅

Full menu bar via `Commands`; nothing important button-only:

- **File:** New Playlist (⌘N), Close (⌘W).
- **Edit:** standard ⌘C/⌘V, Find (⌘F).
- **Controls:** Play/Pause (Space), Next (⌘→), Previous (⌘←), Increase/Decrease
  Volume, Shuffle, Repeat, Star (⌘L or similar).
- **View:** Show/Hide Column Browser, Show/Hide Up Next, sidebar toggle, column
  visibility, sort.
- **Window / Help:** standard.

Standard editing/window shortcuts (⌘C/⌘S/⌘W) behave as users expect.

## Liquid Glass & appearance ✅

- Use **standard SwiftUI controls and materials** (`.background(.regularMaterial)`,
  system control styles, `NavigationSplitView`, `Table`, toolbars) so the UI
  **automatically adopts Liquid Glass on macOS 26** while staying clean and
  native on Sequoia.
- **Do not hard-depend on Tahoe-only APIs.** Guard any with
  `if #available(macOS 26, *)` and provide a Sequoia fallback.
- Respect Light/Dark automatically; no hardcoded colors — use semantic/system
  colors and materials.

## Accessibility (from the start) ✅

- Full **VoiceOver** labels/traits on transport, rows, scrubber, artwork.
- **Dynamic Type**: use text styles, avoid fixed font sizes; verify table/
  header reflow.
- **Increased contrast** and **reduce transparency/motion** honored (don't
  fight `accessibilityReduceTransparency`).
- **Full keyboard navigation**: every action reachable without the mouse;
  logical focus order; visible focus ring.

## Drag-and-drop ✅

- Drag rows → playlists / Up Next (internal).
- Accept audio files dropped on the window/dock to **enqueue** — but note v1 is
  streaming-only/server-backed, so local-file drops are matched to server items
  where possible or flagged as unsupported (decide in M? ; see `06`). ⏳ for
  full local-file playback.

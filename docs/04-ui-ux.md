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
┌──────────────────────────────────────────────────────────┐
│ Toolbar: transport ·· [LCD now-playing] ·· volume · panel │
├──────────┬───────────────────────────────┬───────────────┤
│ 🔍 Search│ [ Genre ][ Artist ][ Album ]  │ NOW PLAYING ✕ │
│ Sidebar  ├───────────────────────────────┤  hero artwork │
│ (Library │                               │  title/artist │
│  /Play-  │  Track Table (dense,          │  scrubber ·   │
│  lists)  │  sortable)                    │  transport    │
│          │                               │  UP NEXT list │
└──────────┴───────────────────────────────┴───────────────┘
```

The now-playing experience lives in the window's unified toolbar: transport
leading, a centered "LCD" display (artwork, title, artist — album,
elapsed/total, a hairline progress bar), volume + panel toggle trailing. The
search field is pinned at the top of the sidebar (Music-style,
`.searchable(placement: .sidebar)`) so it never collapses or migrates when the
toolbar gets tight. Clicking the LCD toggles the **Now Playing panel** — a
trailing inspector with a hero card for the current track above the Up Next
queue.

> Toolbar gotcha: SwiftUI on macOS cannot host custom toolbar items in the
> strip above the sidebar — attaching them to the sidebar column breaks the
> NSToolbar layout (items dumped into overflow), and `.automatic` placement
> there silently drops the whole toolbar. Keep all items on the split view.

## Sidebar (`NavigationSplitView`) ✅

Grouped like iTunes, using `Section`s and SF Symbols:

- **Library**
  - Albums · Artists · Songs · Favorites (starred). Genre browsing lives in
    the column browser (no separate sidebar item).
- **Playlists**
  - The user's server playlists (live from `getPlaylists`), each selectable;
    context menu for rename/delete; "+" to create.

Selection drives the detail area. `LibraryModel` backs the content.

## Track table ✅

- AppKit-backed **`MusicTrackTable`** (via the `TrackTableView` wrapper — see
  the M5 notes in `PROGRESS.md`) with click-to-sort columns: Title, Artist,
  Album, Genre, Time, plus the now-playing speaker and ★ columns. Per-view
  column sets.
- Dense row height; right-aligned monospaced-digit time; edge-to-edge stripes.
- Double-click (or ⏎) plays the row and sets the queue from the current view;
  **⌥-double-click queues it next**.
- Context menu: Play, Play Next, Add to Up Next, Add to Playlist ▸ (incl. New
  Playlist…), Add/Remove Favorites, Go to Album / Go to Artist (single
  selection); playlist mode adds Move to Top/Up/Down/Bottom + Remove from
  Playlist.
  ⏳ Pending: Get Info.
- Multi-select; drag selected rows to a playlist in the sidebar.
  ⏳ Pending: dropping rows into the Up Next panel.

## Column browser ✅

Above the track table, a horizontal multi-pane browser filtering
**Genre → Artist → Album** (iTunes pattern). Selecting in a left pane narrows
the panes to its right and the track table below. Implemented as adjacent
selectable lists; selections are part of restorable view state. Toggleable
(View menu / shortcut) so users who prefer a plain table can hide it.

## Now Playing panel (Up Next / play queue) ✅

- A trailing inspector (`NowPlayingPanel`, ~344pt), headerless (closed via the
  toolbar toggle, the LCD, or ⌘U). Only presentable while something is playing
  or queued — otherwise it stays hidden (no empty state) and its toggles are
  disabled; the stored preference survives, so it reappears when playback
  starts. Contents: a full-bleed square hero artwork flush with
  the panel edges and extending to the window's very top (the panel ignores
  the top safe area — its slice of the toolbar has no items), then
  title/artist/album, a slim scrubber with elapsed/total times, and a
  prominent transport cluster (accent-filled play) flanked by shuffle + repeat
  toggles (accent when active) — all on a 16pt inset shared with the Up Next
  rows.
- Below, the **Up Next** queue: **reorderable** by drag (`.onMove`),
  hover-to-remove, "play from here" via a hover play button on the artwork
  (and the context menu), clear upcoming. Edits mutate `PlayerModel.queue`;
  gapless pre-buffer target updates accordingly (see `03`).
  Gotcha: rows must NOT carry `.contentShape`/tap gestures — they claim the
  mouse-down and silently disable the List's row-drag reordering.

## Now-playing toolbar ✅

- Transport (prev / accent play circle / next) at the leading edge; a centered
  "LCD" capsule with cached artwork (see `05`), centered title and
  artist — album, elapsed/total time, and a hairline accent progress bar along
  its bottom edge; volume + panel toggle trailing. Clicking the LCD (or the
  trailing toolbar button, or ⌘U) toggles the Now Playing panel.

## MenuBarExtra Now Playing panel ✅

- `MenuBarExtra` with **`.menuBarExtraStyle(.window)`** dropping a compact
  panel modeled on the modern macOS Music / Control Center Now Playing dropdown
  (this replaces the old iTunes MiniPlayer):
  - Large artwork, title/artist, the inspector's slim accent scrubber with
    elapsed/total times, and its transport row (accent play circle flanked by
    shuffle + repeat toggles).
  - ⏳ Pending: volume + output-device quick-switch (output device lives in
    Settings → Playback for now).
- Observes the same `PlayerModel` instance as the main window (shared via the
  environment) so it never drifts. Works while the main window is closed.

## Global search ✅

- A search field pinned at the top of the sidebar (`.searchable(placement:
  .sidebar)`), calling `search3` with debounce + task cancellation (see `02`).
  Previous results stay visible while the next query runs (no spinner flash).
- Results: an Artists shelf (circular portraits) and an Albums shelf (covers,
  same cell as Favorites) that open the regular artist/album screens in place,
  above the songs in the shared `TrackTableView` (stripes,
  double-click-to-play, context menu, favorites, now-playing indicator).

## Navigation (no stack) ✅

- The app deliberately has **no `NavigationStack`** — no push/pop and no
  toolbar back/forward chrome. `Navigator` (environment observable) holds the
  in-place state: an opened album renders over the current section with an
  inline accent "‹ Back" link; switching sections or editing the search query
  closes it.
- Artists is a master-detail split (artist list left, albums right); search
  hands an artist off via `Navigator.pendingArtist` (selects it in the Artists
  section and clears the query).
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

# 05 — Local Metadata & Artwork Caching

> **Decision (updated):** The **SwiftData metadata cache was dropped.** The app
> is network-required by design — you can't stream music with the server down,
> so caching library *metadata* for offline browsing adds complexity for little
> value. Library metadata stays **in-memory** in `LibraryModel`, fetched per
> session. The one thing we *do* cache aggressively is **artwork** (immutable),
> on disk — see "Artwork cache". The SwiftData section below is retained as
> historical context and is **not implemented**.

Caching here is **artwork only** — there is **no audio/offline caching** and no
metadata persistence (streaming-only, network-required).

## Artwork cache (implemented)

`Services/ArtworkCache.swift` is a two-tier cache keyed by `coverArt id + pixel
size`:
- **In-memory** `NSCache` (count-bounded) for the hot path, plus a per-id size
  index so a different-size request can show an already-loaded variant instantly
  (no placeholder flash).
- **On-disk** store under `Caches/<bundleId>/Artwork`, filenames are the SHA-256
  of the key; the original downloaded bytes (webp/jpeg) are written as-is.
  Because cover art is immutable, a disk hit is authoritative and kept
  indefinitely — artwork loads instantly across launches and survives network
  blips. Disk + network I/O run off the main actor.

## Persistence: SwiftData 🔶 (dropped — historical)

*(Not implemented. Kept for context.)* Originally we planned **SwiftData** for a
metadata cache:
- Modern, value-/macro-based, pairs cleanly with `@Observable` and SwiftUI.
- macOS 15 deployment supported it; schema small and read-mostly.
- Core Data was the escape hatch if a hard limitation surfaced.

### Model schema (cached server metadata)

`@Model` classes mirroring the API value types, keyed by the server `id`:

- `CachedArtist` — id, name, albumCount, starred, sort key.
- `CachedAlbum` — id, name, artist(+id), year, genre, coverArtId, songCount,
  duration, starred; relationship → songs.
- `CachedSong` — id, title, artist(+id), album(+id), track, disc, year, genre,
  duration, bitRate, suffix, contentType, coverArtId, starred.
- `CachedGenre` — name, songCount, albumCount.
- `CachedPlaylist` — id, name, owner, public, songCount, duration, changed;
  ordered relationship → entries (song ids).
- `LibrarySyncState` — per-list offsets/timestamps for pagination + staleness.

Notes:
- Store the server `id` as the unique key; upsert on fetch.
- Keep these as a **cache, not the source of truth** — the server is
  authoritative. Refresh on connect and on demand; treat entries as
  invalidatable.
- Map `@Model` objects to `Sendable` value types before crossing actor
  boundaries (`@Model` types are `@MainActor`-bound).

## Pagination & lazy loading ✅

- Library lists (`getAlbumList2`, `getSongsByGenre`, `search3`) fetch in pages
  (size ~100–200) and persist pages into SwiftData.
- Views read from the store and trigger the next page near the scroll end.
- `LibrarySyncState` tracks the next offset and whether a list is exhausted, so
  pagination logic lives in one place (`LibraryStore`).
- Refresh policy: revalidate a list when it's older than a threshold or on
  explicit pull/refresh; reconcile by upsert + prune of removed ids.

## Artwork cache ✅

`ArtworkCache` (an actor or `@MainActor` cache) — decode once, reuse resized
variants:

- Key by `coverArtId` **+ target pixel size** (so a list thumbnail and the
  header hero are separate entries).
- Fetch via `getCoverArt` requesting a server-resized `size` close to the
  needed points × screen scale (avoids pulling full-res for a 40 pt thumbnail).
- Two tiers:
  - **In-memory** `NSCache<NSString, NSImage>` (or a custom LRU) — bounded by
    total cost; evicts under memory pressure.
  - Optionally a small **on-disk** thumbnail cache in
    `Caches/` (system-purgeable) to avoid re-downloading across launches.
    Mark as cache so the OS can reclaim it; this is *artwork*, not audio, so it
    doesn't violate "no offline caching."
- Never reload full-resolution artwork on selection; the now-playing header
  uses a single moderate hero size, list rows use thumbnails.
- Respond to `NSCache` automatic eviction + explicit purge on memory warnings.

## Memory-footprint tactics (consolidated) ✅

- **Stream, don't load:** audio is streamed and decoded incrementally; only the
  next track is pre-buffered (see `03`).
- **Release aggressively:** completed PCM buffers and finished-track temp files
  are freed immediately; artwork is bounded and purgeable.
- **Paginate:** never hold an entire large library's rows in memory; rely on
  `Table` virtualization + paged store reads.
- **Right-size images:** request server-resized artwork; cache by exact target
  size; downscale on decode.
- **Bounded caches:** cost-limited `NSCache`; SwiftData fetches are paged, not
  whole-table.

## Threading ✅

- SwiftData `ModelContext` work on the main actor (its objects are
  main-actor-bound); heavy decode/transform off-main, then hand `Sendable`
  values back to update the store/UI.
- Artwork fetch/decode off the main thread; publish the finished `NSImage` to
  the main actor.

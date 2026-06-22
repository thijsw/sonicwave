# 02 — Server & API Layer (OpenSubsonic)

Target the **OpenSubsonic** API (a backward-compatible superset of Subsonic),
with **Navidrome** as the reference server. Single server connection, no
multi-server profiles.

References to consult during implementation:
- Subsonic API: <http://www.subsonic.org/pages/api.jsp>
- OpenSubsonic spec: <https://opensubsonic.netlify.app/>

## Authentication ✅

Two modes; chosen automatically based on server capability + user choice in
Settings:

1. **Standard Subsonic token+salt** (always available)
   - Generate a random `salt` per request (or per session) and
     `t = md5(password + salt)` using `Insecure.MD5` (CryptoKit).
   - Send `u` (username), `t` (token), `s` (salt). **Never** send the raw
     password; never persist the token — persist only the password in Keychain.

2. **OpenSubsonic API-key auth** (where supported)
   - Send the pre-issued API key per the OpenSubsonic auth extension instead of
     `u/t/s`. Server support varies — gate on capability detection (below).

Common params on every request: `v` (protocol version we target, e.g.
`1.16.1`), `c=Sonicwave` (client name), `f=json` (JSON responses).

Credentials live in the **Keychain** (`AuthStore`): server base URL, username,
and either password or API key. The connection is configured in the native
Settings window with a **Test Connection** button that calls `ping`.

## Capability detection 🔶

On connect, call `getOpenSubsonicExtensions` (and inspect the
`openSubsonic`/`serverVersion`/`type` fields on the `ping`/responses) to learn:
- whether API-key auth is supported,
- which optional extensions exist (e.g. `formPost`, transcode offsets,
  song lyrics — informational for v1).

Fall back to token+salt and classic behavior when an extension is absent.

## Networking client ✅

`actor SubsonicClient` over `URLSession`:

- `func request<T: Decodable>(_ endpoint: Endpoint) async throws(SubsonicError) -> T`
- A `RequestBuilder` composes base URL + endpoint path (`/rest/<method>`) +
  common params + auth params + endpoint params. URL-encode everything.
- One configured `URLSession` (ephemeral or default, no disk cache for API
  JSON; artwork/stream handled separately).
- Decoding off the main actor; map to `Sendable` value types before returning.
- Respect cancellation (`Task` cancellation → cancels the data task) for
  search-as-you-type and view teardown.

### Response envelope

All Subsonic JSON is wrapped: `{ "subsonic-response": { status, version, … } }`.
A generic `SubsonicResponse<T>` decodes the envelope; on
`status == "failed"` decode the `error` object and throw.

## Endpoint map (v1)

Grouped by feature. All are `GET` on `/rest/<method>`.

### Connection
- `ping` — connection/auth test.
- `getOpenSubsonicExtensions` — capability detection.
- `getMusicFolders` — top-level folders (used to scope library queries).

### Library browse
- `getAlbumList2` — albums, with `type` (`alphabeticalByName`, `newest`,
  `recent`, `frequent`, `byGenre`, …), `size`, `offset` → **pagination**.
- `getArtists` — full artist index (grouped alphabetically).
- `getArtist` — one artist's albums.
- `getAlbum` — one album's songs.
- `getGenres` — genre list (with counts).
- `getSongsByGenre` — songs in a genre, with `count`/`offset` → pagination.
- `getSong` — single song metadata (detail/refresh).

### Favorites / starred
- `getStarred2` — starred artists/albums/songs.
- `star` / `unstar` — toggle favorite by `id` (song/album/artist).

### Search
- `search3` — unified search with `query`, and per-type
  `artistCount/albumCount/songCount` + `*Offset` → pagination.

### Playlists
- `getPlaylists` — the user's playlists.
- `getPlaylist` — one playlist's entries (ordered).
- `createPlaylist` — name + songId list (or from existing playlist).
- `updatePlaylist` — rename, add/remove songs, **reorder** via
  `songIndexToRemove` + re-adds (see `04` for the reorder strategy), comment,
  public flag.
- `deletePlaylist` — by `id`.

### Streaming & artwork
- `stream` — audio stream by `id`. Transcoding params:
  - default: omit `format`/`maxBitRate` → original file.
  - when transcoding enabled in Settings: `format` (e.g. `mp3`, `opus`) +
    `maxBitRate` (kbps). Optional `timeOffset` for resume/seek-on-server
    fallback (we primarily seek locally — see `03`).
- `getCoverArt` — artwork by `id`, with `size` to request a server-resized
  thumbnail (used by `ArtworkCache`).

## Models (Codable, value types) ✅

`Sendable struct`s mirroring the JSON, e.g. `Song`, `Album`, `AlbumID3`,
`ArtistID3`, `Genre`, `Playlist`, `SearchResult3`, `Starred2`. Keep DTOs close
to the wire, then map to UI value types where the wire shape is awkward. Notable
fields: `id`, `title`/`name`, `artist`/`artistId`, `album`/`albumId`,
`coverArt`, `duration`, `track`, `discNumber`, `year`, `genre`, `bitRate`,
`suffix`, `contentType`, `starred` (date → `isStarred`).

Decoding notes: Subsonic returns single-vs-array inconsistencies and
string-encoded numbers in places; write tolerant decoders + fixtures (see `08`).

## Errors ✅

```
enum SubsonicError: Error, Sendable {
  case transport(URLError)
  case http(status: Int)
  case decoding(String)
  case api(code: Int, message: String)   // Subsonic error codes:
                                          // 0 generic, 10 missing param,
                                          // 20 client too old, 30 server too old,
                                          // 40 wrong credentials, 41 token auth
                                          // unsupported, 50 not authorized,
                                          // 60 trial over, 70 not found
  case notConfigured
}
```

Map code `40/41/50` to a re-authenticate / open-Settings flow; `70` to
empty-state UI; transport errors to a retry affordance.

## Pagination strategy ✅

- Page size constant (e.g. 100–200) for `getAlbumList2`, `getSongsByGenre`,
  `search3`.
- Library views request the next page when the user scrolls near the end
  (`onAppear` of a trailing sentinel row, or `Table` scroll position).
- Persist fetched pages into `LibraryStore` (SwiftData) so re-entry is instant
  and offset bookkeeping is centralized (see `05`).

## Transcoding setting → `stream` params ✅

Settings exposes: **Stream original** (default) or **Transcode** with a format
picker (`mp3`/`opus`/`aac`) and a max bitrate. `PlaybackService` asks
`SubsonicClient` for the stream URL with the appropriate params. Document that
transcoding shifts CPU to the server and can affect gapless (re-encoded
boundaries) — note for the `03` spike.

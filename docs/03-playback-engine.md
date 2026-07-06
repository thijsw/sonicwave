# 03 — Playback Engine (`AVAudioEngine`)

Playback is **streaming-only** and must be **gapless** across album tracks,
small in memory footprint, fully off-main-thread for I/O and decode, and wired
to the system Now Playing center (see `06`). We commit to **`AVAudioEngine`**
(✅) for sample-accurate gapless and headroom for future EQ / visualizations /
explicit output-device routing — accepting that we must fetch and decode the
stream ourselves.

> Why not `AVQueuePlayer`: it streams HTTP natively with far less code, but
> gapless across *separate, independently-encoded* remote files isn't reliably
> sample-perfect, and it gives us little control over the output device graph
> and future DSP. `AVAudioEngine` makes gapless a property of *our* scheduling.

## Engine graph ✅ (implemented: single node, canonical timeline format)

```
AVAudioEngine ─ AVAudioPlayerNode ─► main mixer ─► output node ─► device
```

- **One** `AVAudioPlayerNode`. Every track decodes to one canonical timeline
  format and consecutive tracks are scheduled back-to-back on the same node
  without stopping it — gapless falls out of continuous scheduling.
- Volume via the mixer; `volume` mirrored in `PlayerModel`.
- All scheduling and engine mutation happen inside `PlaybackService` (an
  `actor`), never on views.

### How the single-node design was reached
The original plan was dual nodes (A/B) so track N+1 could use its own format
while N finished. The M4 spike (2026-06-22) resolved to the
**canonical-format, single-node** variant instead: since every track is
decoded (resampling only when needed) into the timeline's format, one
connection format suffices, and the next track's buffers are simply appended
to the same node ahead of the play head. Pre-buffering uses a pull model
(`.wantNext` → `enqueueNext`), and track boundaries are detected from the
node's sample-time spans (`.trackChanged`). Audible seam human-verified
2026-07-03.

**Hardware sample-rate matching (2026-07-05, Audirvana/Roon-style):** with
"Match hardware sample rate" on (Settings → Playback, default on), each hard
start re-derives the timeline format from the track's **native sample rate**
(the decoder picks its output format at source discovery — no software
resample), reconnects the node when the rate differs from the current
connection, and sets the output device's **nominal hardware rate**
(`kAudioDevicePropertyNominalSampleRate`, closest supported) to match — so
nothing resamples between file and DAC. Gapless followers join the running
timeline's format (resampled only if they differ, e.g. a mixed-rate queue).
The device-rate switch fires config-change notifications; those are treated
as echoes of the deliberate change (see the recovery echo guard). External
rate meddling while playing is corrected on the next config change. With
matching off, timelines return to the fixed 44.1 kHz base format and the
device's rate is never touched. Verified live against a USB DAC (CXA81,
44.1k–705.6k): 48 kHz pre-set snapped to 44.1 kHz on play; toggle off left
an external 48 kHz set untouched. Remaining ideal-world gaps: bit depth
stays float32 through the mixer (lossless for ≤24-bit sources), and
exclusive/hog-mode access is not implemented.

## Streaming decode source ✅ (decision: Option A — progressive decode)

We need compressed audio (mp3/aac/opus/flac/…) from an HTTP `stream` URL turned
into PCM `AVAudioPCMBuffer`s to schedule. Two designs were considered;
**Option A is the committed approach** (decided 2026-06-22). Option B is kept on
record as a fallback if A's edge cases prove too costly.

### Option A — Progressive decode (principled, low memory) ✅ (CHOSEN for v1)
- Fetch bytes incrementally via `URLSession` (data-delegate → `AsyncStream<Data>`).
- Parse container/packets with **Audio File Stream Services**
  (`AudioFileStreamOpen`/`ParseBytes`) to get audio packets + format.
- Convert compressed packets → PCM with **`AVAudioConverter`**, producing
  `AVAudioPCMBuffer`s.
- Schedule buffers on the player node as they're produced, keeping only a small
  ring of buffers in memory → smallest footprint, true streaming.
- Most complex (Core Audio C APIs, packet/format edge cases, seeking) — this is
  the project's key spike.

### Option B — Temp-file staging ⏳ (fallback, not the v1 path)
- `URLSession` download the stream to an ephemeral temp file (disk, not RAM).
- Once enough is staged, read PCM in chunks via `AVAudioFile` and schedule.
- Simpler and robust; uses disk (ephemeral). Slightly higher latency to first
  audio; seeking is easy (read from offset).

**Decision (2026-06-22):** ship **Option A** (progressive decode) for v1.
The engine code stays agnostic behind `protocol AudioStreamSource`, so
Option B remains droppable-in if needed. The implemented seam is push-based
(the loader feeds bytes in; decoded PCM comes out as a stream):

```swift
protocol AudioStreamSource: AnyObject {
  /// Decoded PCM buffers in playback order; finishes when the input ends.
  var buffers: AsyncStream<SendablePCMBuffer> { get }
  /// Feed freshly-received compressed bytes into the parser.
  func parse(_ data: Data)
  /// Signal end-of-input; flushes and finishes the `buffers` stream.
  func finish()
}
```

Hardening that landed after the decision (see `PROGRESS.md` for the full
forensics): the converter tail is flushed at end-of-stream (`flushDecoder`);
linear-PCM sources (WAV/AIFF) are wrapped in `AVAudioPCMBuffer` (an
`AVAudioCompressedBuffer` is invalid for PCM and decoded to garbage);
per-batch decoder outputs are **consolidated into ~1-second buffers** so a
burst of tiny `scheduleBuffer` calls can't starve the audio IO thread. Known
limitation: magic-cookie formats (AAC-in-MP4) — `AVAudioConverter` has no
cookie API; ADTS/MP3/FLAC/WAV/AIFF are fine.

## Gapless pre-buffering ✅ (pull model)

- When track N finishes **decoding** (well ahead of the play head — decode
  runs faster than real time, bounded by the read-ahead throttle below),
  `PlaybackService` emits `.wantNext(afterIndex:)`.
- `PlayerModel` answers with `enqueueNext(...)` (or `enqueueNoMore()`); the
  successor's decode starts and its buffers are appended to the same node's
  timeline — no gap, no node swap.
- Each track occupies a **span** of the node's sample timeline; crossing a
  span boundary emits `.trackChanged(index)`. Queue edits after hand-off are
  reconciled through `PlayerModel`'s `spanPositions` map.
- **Bounded read-ahead:** scheduling stays between ~8 s and ~15 s ahead of the
  playhead — beyond that the URLSession transfer is suspended and decoding
  pauses until playback drains (bounds memory, smooths scheduling).

## Seeking ✅ (transcode-aware)

Pure forward streaming has no random access, so `seek(to:)` re-opens the
stream (a hard restart on the same path as manual skip):
- **Transcoded streams:** re-request `stream` with `timeOffset` (seconds) —
  the OpenSubsonic `transcodeOffset` extension; the server starts encoding at
  the target.
- **Original-file streams (the default):** the server *ignores* `timeOffset`,
  so the client streams from 0 and `ProgressiveAudioSource` **discards decoded
  output up to the seek point** (`skipSeconds`/`skipFrames`, sample-precise,
  format-independent). The re-read is fine on a fast connection; a byte-range
  optimization is a possible future refinement.
- `PlayerModel.position` + Now Playing elapsed time update to the seek target;
  scrubbers seek once on release, not per drag tick.

## Position updates — throttled ✅

- Derive position from the player node's sample time
  (`lastRenderTime` → `playerTime`) rather than a wall clock.
- Publish to `PlayerModel` at **~4–10 Hz** (a `Timer`/`AsyncTimerSequence`),
  and only while a position-consuming view is visible. Never drive the UI at
  buffer/render rate. Update `MPNowPlayingInfoCenter` elapsed time on the same
  cadence (or less).

## Output device selection & route changes ✅ (human-verified 2026-07-05)

- **No `AVAudioSession` on macOS** — it's iOS-only. Use Core Audio + the
  engine instead.
- `AudioOutputDevices` (Playback/) enumerates output-capable devices via Core
  Audio, resolves the persisted **UID** to a live device id, and filters
  transient private aggregates. The picker lives in Settings → Playback
  (System Default + devices; a "(disconnected)" row keeps a vanished choice
  visible).
- `PlaybackService.setOutputDevice(uid:)` persists the choice and points the
  output unit at it (`kAudioOutputUnitProperty_CurrentDevice`).
- Route/config changes: `AVAudioEngineConfigurationChange` **plus** a
  `kAudioHardwarePropertyDevices` listener (`AudioDeviceListObserver`) — the
  engine notification does *not* fire when a pinned device vanishes.
- **Recovery model:** a live device swap silently wedges the render graph when
  hardware formats differ, so every route change (manual switch, vanish →
  fallback, return → re-pin) **rebuilds the engine and hard-restarts the
  stream at the playhead** (reusing the seek path) — a sub-second gap,
  reliable on any hardware. Recovery-provoked config-change notifications are
  swallowed as echoes (1 s guard). Sonicwave never touches the system default;
  other apps' routing is untouched.

## Power management ✅

- Wrap active playback in
  `ProcessInfo.processInfo.beginActivity(options: [.userInitiated,
  .idleSystemSleepDisabled], reason: "Playing audio")` and end the activity on
  stop/pause so macOS doesn't App-Nap-throttle or sleep mid-track.

## Memory footprint ✅

- Keep only a small ring of scheduled PCM buffers per active node; release
  completed buffers in their completion handlers.
- Tear down the finished track's source + temp file immediately on transition.
- Stream rather than loading whole files into RAM; pre-buffer just the next
  track, not the whole queue.
- Coordinate artwork release with `ArtworkCache` (see `05`).

## Interface to the rest of the app

`PlaybackService` (actor) exposes async intent —
`play(songId:suffix:duration:index:from:)` (hard start / seek),
`enqueueNext(...)`/`enqueueNoMore()` (gapless pull replies), `pause()`,
`resume()`, `stop()`, `seek(to:)`, `setOutputDevice(uid:)`, `setVolume(_:)` —
and emits an `AsyncStream<PlaybackEvent>` (`.stateChanged`, `.position`,
`.trackChanged`, `.wantNext`, `.ended`, `.failed`) that `PlayerModel` consumes
on the main actor and re-publishes for the UI and `NowPlayingCenter`.

## Spike checklist (M4 exit criteria)
- [x] Gapless verified on a known gapless album — Abbey Road medley, zero
      underruns/HAL overloads; human-confirmed seamless (2026-07-03).
- [ ] Sample-rate change between tracks (e.g. 44.1k → 48k) — handled by design
      (followers resample into the timeline format); an audible cross-rate
      transition is untested until the library has mixed-rate tracks.
- [x] Seek accurate; position UI stable at ~5 Hz (scrub-to-2:00 verified,
      0 overloads).
- [x] Output device switch mid-track recovers without crash/restart-from-zero
      (USB DAC ↔ speakers, vanish/replug — 2026-07-05).
- [x] Memory bounded over a full-album play (8–15 s read-ahead throttle; no
      whole-track decode in RAM).

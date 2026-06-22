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

## Engine graph ✅

```
              ┌─ AVAudioPlayerNode A ─┐
AVAudioEngine ┤                       ├─► main mixer ─► output node ─► device
              └─ AVAudioPlayerNode B ─┘
```

- Two `AVAudioPlayerNode`s (A/B), both attached to the engine and connected to
  the main mixer. The **current** track plays on one node while the **next**
  track's initial buffers are pre-scheduled — gapless is achieved by scheduling
  N+1 to begin exactly when N's last buffer completes.
- Volume via the mixer / node `volume`; `volume` mirrored in `PlayerModel`.
- All scheduling and engine mutation happen inside `PlaybackService` (an
  `actor`), never on views.

### Why dual nodes (not just consecutive scheduling on one node)
A single node can chain buffers gaplessly *if all buffers share one format*.
Different tracks frequently differ in sample rate/channel count, which a single
node connection can't switch mid-stream. Dual nodes (each (re)connected at the
track's native format, or fed through `AVAudioConverter` to a common mixer
format) let track N+1 use its own format while N is still finishing. Common
approach: **convert every track to one canonical mixer format** (e.g. 44.1/48k
float stereo) so a single connection format suffices, and use the second node
purely to overlap load/schedule of N+1. Decide canonical-format-vs-reconnect in
the spike.

**Implemented (M4, 2026-06-22):** the spike resolved to the **canonical-format,
single-node** variant. `PlaybackService` decodes every track to a fixed
canonical format (44.1 kHz / stereo / float) and schedules consecutive tracks
back-to-back on **one** `AVAudioPlayerNode` without stopping it — gapless falls
out of continuous scheduling, and sample-rate changes are absorbed by resampling
to the canonical format. The second node proved unnecessary because the next
track is decoded ahead of the play head and its buffers are appended to the same
node. Pre-buffering uses a pull model (`.wantNext` → `enqueueNext`), and track
boundaries are detected from the node's sample-time spans (`.trackChanged`).
Still pending **device verification** of the audible seam.

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
Known rough edges to harden during the M4 spike: compressed-format **magic
cookie** handling (AAC/ALAC), and **seek** (pure forward streaming has no random
access — seek is implemented by re-opening the stream at a `timeOffset`/byte
range, see Seeking below). The engine code stays agnostic behind a
`protocol AudioStreamSource`, so Option B remains droppable-in if needed:

```
protocol AudioStreamSource: Sendable {
  var format: AVAudioFormat { get async }
  var duration: TimeInterval? { get async }
  func nextBuffer(frameCapacity: AVAudioFrameCount) async throws -> AVAudioPCMBuffer?
  func seek(to time: TimeInterval) async throws
}
```

Temp files from Option B are deleted as soon as the track is done (aggressive
release).

## Gapless pre-buffering ✅

- Track N+1's `AudioStreamSource` is created and primed when N crosses a
  threshold (e.g. ~10–15 s remaining, or when N's buffers are nearly all
  scheduled).
- N+1's leading buffers are scheduled on the second node with a sample-accurate
  start (no `play()` gap). When N's final buffer's completion handler fires,
  N+1 is already audible-ready, so the transition has no silence.
- Roles of node A/B swap each track. The just-finished source is torn down and
  its buffers/temp file released.

## Seeking ✅ (Option A approach)

Pure forward streaming has no random access, so `seek(to:)` **re-opens the
stream at the target offset**:
- Tear down the current source/player scheduling, reset the position base to the
  seek time.
- Re-request `stream` with `timeOffset` (seconds) — supported by Navidrome for
  transcoded streams — and resume progressive decode from there. (HTTP `Range`
  is the fallback where the server honors byte ranges.)
- Update `PlayerModel.position` + Now Playing elapsed time to the seek target.

This is heavier than local seeking but is the only reliable option for forward
streams; accuracy/latency are part of the M4 spike checklist.

## Position updates — throttled ✅

- Derive position from the player node's sample time
  (`lastRenderTime` → `playerTime`) rather than a wall clock.
- Publish to `PlayerModel` at **~4–10 Hz** (a `Timer`/`AsyncTimerSequence`),
  and only while a position-consuming view is visible. Never drive the UI at
  buffer/render rate. Update `MPNowPlayingInfoCenter` elapsed time on the same
  cadence (or less).

## Output device selection & route changes ✅

- **No `AVAudioSession` on macOS** — it's iOS-only. Use Core Audio + the
  engine instead.
- `OutputDeviceService` enumerates output devices via Core Audio
  (`AudioObjectGetPropertyData` on the system object) and lets the user pick one
  (surfaced in a menu / Settings — audiophiles expect this).
- Set the engine's output to the chosen device by setting the
  `AVAudioOutputNode`'s underlying audio unit current device
  (`kAudioOutputUnitProperty_CurrentDevice`).
- Observe device/route changes: `AVAudioEngineConfigurationChange`
  notification and Core Audio property listeners
  (`AudioObjectAddPropertyListener` on default-device / device-list). On change
  (headphones unplugged, AirPods connect, device removed): pause if needed,
  rebuild/reconnect the engine graph at the new device's format, and resume.

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

`PlaybackService` (actor) exposes async intent — `load(queue:startAt:)`,
`play()`, `pause()`, `next()`, `previous()`, `seek(to:)`,
`setOutputDevice(_:)`, `setVolume(_:)` — and emits a stream of
`(PlaybackState, position, currentIndex)` that `PlayerModel` consumes on the
main actor and re-publishes for the UI and `NowPlayingCenter`.

## Spike checklist (M4 exit criteria)
- [ ] Gapless verified on a known gapless album (no audible seam, no overlap).
- [ ] Sample-rate change between tracks handled (e.g. 44.1k → 48k).
- [ ] Seek accurate within ~50 ms; position UI stable at 4–10 Hz.
- [ ] Output device switch mid-track recovers without crash/restart-from-zero.
- [ ] Memory stable over a full-album play (no buffer leak).

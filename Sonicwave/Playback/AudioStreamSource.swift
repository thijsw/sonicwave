import AVFoundation

/// Transfers ownership of a decoded PCM buffer across task boundaries. The
/// buffer is produced by the decoder and consumed by the player exactly once,
/// so unchecked Sendable is safe here. See docs/03-playback-engine.md.
struct SendablePCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Abstraction over a streaming PCM source, so the engine/scheduler is
/// independent of how audio is fetched and decoded. Option A
/// (`ProgressiveAudioSource`) is the v1 implementation; Option B (temp-file)
/// could conform to the same shape if ever needed. See docs/03-playback-engine.md.
protocol AudioStreamSource: AnyObject {
    /// Decoded PCM buffers in playback order; finishes when the input ends.
    var buffers: AsyncStream<SendablePCMBuffer> { get }
    /// Feed freshly-received compressed bytes into the parser.
    func parse(_ data: Data)
    /// Signal end-of-input; flushes and finishes the `buffers` stream.
    func finish()
}

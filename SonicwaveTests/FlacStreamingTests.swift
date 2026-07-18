import Testing
import Foundation
import AVFoundation
@testable import Sonicwave

/// Regression: FLAC streams must decode fully through the progressive
/// pipeline. Constructing AVFoundation buffers inside the AudioFileStream
/// packets callback silently corrupts the FLAC parser — after a few frames
/// every ParseBytes returns 'wht?' and decode stops (~0.5s of audio from a
/// 4-minute track, no failure message). The fix defers all buffer building
/// until after ParseBytes returns. See PROGRESS 2026-07-16.
struct FlacStreamingTests {
    /// Encode a real .flac via AVAudioFile: 3s of stereo sine at 44.1k.
    private func makeFlac() throws -> (data: Data, frames: AVAudioFramePosition) {
        let sampleRate = 44_100.0
        let frames = AVAudioFrameCount(sampleRate * 3)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let sine = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        sine.frameLength = frames
        for channel in 0..<2 {
            let samples = sine.floatChannelData![channel]
            for i in 0..<Int(frames) {
                samples[i] = sinf(Float(i) * 2 * .pi * 440 / Float(sampleRate)) * 0.5
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flac-regression-\(UUID().uuidString).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2
        ]
        // Scoped so the AVAudioFile deinits (flushing the header) before we
        // read the bytes back — close() needs macOS 15, the target is 14.
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                       interleaved: false)
            try file.write(from: sine)
        }
        let data = try Data(contentsOf: url)
        return (data, AVAudioFramePosition(frames))
    }

    @Test func flacDecodesFullyWhenStreamedInChunks() async throws {
        let (flac, expectedFrames) = try makeFlac()
        #expect(flac.count > 10_000)

        let canonical = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let source = ProgressiveAudioSource(outputFormat: canonical)
        source.open(fileTypeHint: audioFileTypeHint(forSuffix: "flac"))

        let buffers = source.buffers
        let consume = Task { () -> AVAudioFramePosition in
            var total: AVAudioFramePosition = 0
            for await box in buffers { total += AVAudioFramePosition(box.buffer.frameLength) }
            return total
        }

        // Small chunks so packetsProc fires many times mid-stream — the
        // pattern that used to corrupt the parser.
        let chunk = 4096
        var offset = 0
        while offset < flac.count {
            let end = min(offset + chunk, flac.count)
            source.parse(flac.subdata(in: offset..<end))
            offset = end
        }
        source.finish()

        let decoded = await consume.value
        #expect(source.failureMessage == nil)
        // Everything (minus at most a trailing converter block) must decode —
        // the corruption bug yielded well under 10% of the file.
        #expect(decoded > expectedFrames - 8_192)
    }
}

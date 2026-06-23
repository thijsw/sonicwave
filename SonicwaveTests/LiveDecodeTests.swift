import Testing
import Foundation
import AVFoundation
@testable import Sonicwave

/// Opt-in integration tests that run against a real OpenSubsonic server. They
/// are **skipped** unless `SONICWAVE_HOST`, `SONICWAVE_USER`, and
/// `SONICWAVE_PASS` are set in the environment, so no credentials are committed.
/// These exercise the live wire format + the Option A decode pipeline end to
/// end. See docs/03-playback-engine.md, docs/08-testing.md.
struct LiveDecodeTests {
    private struct Env {
        let host: URL, user: String, pass: String
    }

    private func liveEnv() -> Env? {
        let e = ProcessInfo.processInfo.environment
        guard let host = e["SONICWAVE_HOST"], let url = URL(string: host),
              let user = e["SONICWAVE_USER"], let pass = e["SONICWAVE_PASS"] else { return nil }
        return Env(host: url, user: user, pass: pass)
    }

    private func client(_ env: Env) -> SubsonicClient {
        let creds = ServerCredentials(baseURL: env.host, username: env.user,
                                      secret: env.pass, authMethod: .tokenSalt)
        return SubsonicClient(credentials: InMemoryCredentialStore(creds))
    }

    @Test func pingAndCapabilities() async throws {
        guard let env = liveEnv() else { return }
        let info = try await client(env).ping()
        #expect(info.status == "ok")
        #expect(info.type != nil)
    }

    @Test func decodesRealStreamToPCM() async throws {
        guard let env = liveEnv() else { return }
        let client = client(env)

        // Pick a real song.
        let body = try await client.send(.randomSongs(size: 1), as: RandomSongsBody.self)
        let song = try #require(body.randomSongs.song?.first)

        // Download the stream (full, original format).
        let url = try await client.streamURL(songId: song.id)
        let (data, _) = try await URLSession.shared.data(from: url)
        #expect(data.count > 0)

        // Feed it through the real progressive decoder and collect PCM.
        let canonical = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let source = ProgressiveAudioSource(outputFormat: canonical)
        source.open(fileTypeHint: audioFileTypeHint(forSuffix: song.suffix))

        // Feed in realistic chunks, then finish so the buffers stream completes.
        let chunkSize = 32 * 1024
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            source.parse(data.subdata(in: offset..<end))
            offset = end
        }
        source.finish()

        // Collect channel-0 PCM and the per-batch boundary indices.
        var samples: [Float] = []
        var boundaries: [Int] = []
        for await box in source.buffers {
            #expect(box.buffer.format.sampleRate == 44_100)
            if let ch = box.buffer.floatChannelData, box.buffer.frameLength > 0 {
                boundaries.append(samples.count)
                samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(box.buffer.frameLength)))
            }
        }
        #expect(samples.count > 44_100) // > ~1 second of PCM
        let streamSeconds = Double(samples.count) / 44_100.0

        // Reference: full duration of the same bytes via AVAudioFile.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-ref.\(song.suffix ?? "mp3")")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let refFile = try AVAudioFile(forReading: tmp)
        let refSeconds = Double(refFile.length) / refFile.fileFormat.sampleRate

        // Completeness: the streaming decode should cover ~the whole track
        // (validates the end-of-stream flush; catches truncation/dropped tail).
        #expect(abs(streamSeconds - refSeconds) < 0.5)

        // Continuity: a per-batch boundary must not be glitchier than the natural
        // interior signal. A dropout/discontinuity at a boundary = crackle.
        let boundarySet = Set(boundaries)
        var maxInterior: Float = 0
        var maxBoundary: Float = 0
        for n in 1..<samples.count {
            let step = abs(samples[n] - samples[n - 1])
            if boundarySet.contains(n) { maxBoundary = max(maxBoundary, step) }
            else { maxInterior = max(maxInterior, step) }
        }
        print("[crackle-live] streamSeconds=\(streamSeconds) refSeconds=\(refSeconds) " +
              "batches=\(boundaries.count) maxInterior=\(maxInterior) maxBoundary=\(maxBoundary)")
        #expect(maxBoundary <= maxInterior * 2)
    }
}

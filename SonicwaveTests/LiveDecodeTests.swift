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

        var totalFrames: AVAudioFramePosition = 0
        for await box in source.buffers {
            totalFrames += AVAudioFramePosition(box.buffer.frameLength)
            #expect(box.buffer.format.sampleRate == 44_100)
        }
        // A real track must decode to a meaningful amount of audio.
        #expect(totalFrames > 44_100) // > ~1 second of PCM
    }
}

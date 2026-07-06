import Testing
import Foundation
import AudioToolbox
@testable import Sonicwave

/// Transcoding-preference resolution and seek (timeOffset) URL plumbing.
/// See docs/03-playback-engine.md, docs/08-testing.md.
struct PlaybackConfigTests {
    private func defaults() -> UserDefaults {
        let store = UserDefaults(suiteName: "PlaybackConfigTests-\(UUID().uuidString)")!
        return store
    }

    @Test func transcodeDisabledYieldsNoParams() {
        let store = defaults()
        store.set(false, forKey: "transcodeEnabled")
        let prefs = TranscodePrefs.current(store)
        #expect(prefs.format == nil)
        #expect(prefs.maxBitRate == nil)
    }

    @Test func transcodeEnabledUsesConfiguredValues() {
        let store = defaults()
        store.set(true, forKey: "transcodeEnabled")
        store.set("opus", forKey: "transcodeFormat")
        store.set(192, forKey: "transcodeMaxBitRate")
        let prefs = TranscodePrefs.current(store)
        #expect(prefs.format == "opus")
        #expect(prefs.maxBitRate == 192)
    }

    @Test func transcodeEnabledFallsBackToDefaults() {
        let store = defaults()
        store.set(true, forKey: "transcodeEnabled")
        let prefs = TranscodePrefs.current(store)
        #expect(prefs.format == "mp3")
        #expect(prefs.maxBitRate == 320)
    }

    @Test func streamURLIncludesTimeOffsetForSeek() async throws {
        let creds = ServerCredentials(
            baseURL: URL(string: "https://music.example.com")!,
            username: "thijs", secret: "sesame", authMethod: .tokenSalt)
        let client = SubsonicClient(credentials: InMemoryCredentialStore(creds))
        let url = try await client.streamURL(songId: "s1", timeOffset: 42)
        let items = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["timeOffset"] == "42")
    }

    @Test func fileTypeHintMapsKnownSuffixes() {
        #expect(audioFileTypeHint(forSuffix: "mp3") == kAudioFileMP3Type)
        #expect(audioFileTypeHint(forSuffix: "flac") == kAudioFileFLACType)
        #expect(audioFileTypeHint(forSuffix: "weird") == 0)
        #expect(audioFileTypeHint(forSuffix: nil) == 0)
    }
}

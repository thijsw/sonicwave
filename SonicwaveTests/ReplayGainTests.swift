import Testing
import Foundation
@testable import Sonicwave

/// ReplayGain math and decoding. The dB→linear conversion is 10^(dB/20);
/// peak clamping guarantees gain × peak ≤ 1.0 (no clipping). See issue #6.
struct ReplayGainTests {
    private func info(trackGain: Double? = nil, albumGain: Double? = nil,
                      trackPeak: Double? = nil, albumPeak: Double? = nil) -> ReplayGainInfo {
        ReplayGainInfo(trackGain: trackGain, albumGain: albumGain,
                       trackPeak: trackPeak, albumPeak: albumPeak)
    }

    @Test func offAndMissingDataAreUnity() {
        #expect(ReplayGainMode.off.linearGain(for: info(trackGain: -8)) == 1)
        #expect(ReplayGainMode.track.linearGain(for: nil) == 1)
        #expect(ReplayGainMode.track.linearGain(for: info()) == 1)
    }

    @Test func decibelsConvertToLinear() {
        // -6.02 dB halves the amplitude; +6.02 dB doubles it.
        #expect(abs(ReplayGainMode.track.linearGain(for: info(trackGain: -6.02)) - 0.5) < 0.001)
        #expect(abs(ReplayGainMode.track.linearGain(for: info(trackGain: 6.02)) - 2.0) < 0.001)
        #expect(ReplayGainMode.track.linearGain(for: info(trackGain: 0)) == 1)
    }

    @Test func peakClampPreventsClipping() {
        // +6 dB wants ×2, but a 0.9 peak only allows ×(1/0.9).
        let gain = ReplayGainMode.track.linearGain(for: info(trackGain: 6, trackPeak: 0.9))
        #expect(abs(gain - Float(1 / 0.9)) < 0.001)
        // Negative gains are never limited by peak.
        let quiet = ReplayGainMode.track.linearGain(for: info(trackGain: -12, trackPeak: 0.9))
        #expect(abs(quiet - 0.2512) < 0.001)
    }

    @Test func modesPreferTheirScopeAndFallBack() {
        let both = info(trackGain: -4, albumGain: -10)
        #expect(ReplayGainMode.track.linearGain(for: both)
            == ReplayGainMode.track.linearGain(for: info(trackGain: -4)))
        #expect(ReplayGainMode.album.linearGain(for: both)
            == ReplayGainMode.album.linearGain(for: info(albumGain: -10)))
        // Album mode falls back to track tags when album tags are absent.
        #expect(ReplayGainMode.album.linearGain(for: info(trackGain: -4))
            == ReplayGainMode.track.linearGain(for: info(trackGain: -4)))
    }

    @Test func absurdBoostIsCapped() {
        #expect(ReplayGainMode.track.linearGain(for: info(trackGain: 40)) == 4)
    }

    @Test func transcodeRetryDecisionIsFirstTimeCurrentTrackOnly() {
        // Retry: first failure, current track, user transcoding off.
        #expect(PlaybackService.shouldRetryViaTranscode(
            alreadyForced: false, timelineStart: true, userFormat: nil))
        // Never loop a retry that itself failed.
        #expect(!PlaybackService.shouldRetryViaTranscode(
            alreadyForced: true, timelineStart: true, userFormat: nil))
        // Pre-buffered followers keep the existing (silent) behavior.
        #expect(!PlaybackService.shouldRetryViaTranscode(
            alreadyForced: false, timelineStart: false, userFormat: nil))
        // The user already transcodes — a failure isn't a format problem.
        #expect(!PlaybackService.shouldRetryViaTranscode(
            alreadyForced: false, timelineStart: true, userFormat: "opus"))
    }

    @Test func songDecodesReplayGainTags() throws {
        let json = Data("""
        {"id":"s1","title":"T","replayGain":
            {"trackGain":-7.25,"albumGain":-6.5,"trackPeak":0.988,"albumPeak":1.0}}
        """.utf8)
        let song = try SubsonicClient.makeDecoder().decode(Song.self, from: json)
        #expect(song.replayGain?.trackGain == -7.25)
        #expect(song.replayGain?.albumPeak == 1.0)
    }
}

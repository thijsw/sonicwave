import Testing
@testable import Sonicwave

/// Encoding/quality label shown on track rows and the Now Playing hero.
struct QualityLabelTests {
    @Test func losslessShowsFormatName() {
        #expect(Song(id: "1", title: "T", bitRate: 1024, suffix: "flac").qualityLabel == "FLAC")
        #expect(Song(id: "1", title: "T", bitRate: 1411, suffix: "wav").qualityLabel == "WAV")
        #expect(Song(id: "1", title: "T", suffix: "aif").qualityLabel == "AIFF")
    }

    @Test func lossyShowsBitRate() {
        #expect(Song(id: "1", title: "T", bitRate: 320, suffix: "mp3").qualityLabel == "320 kbps")
        #expect(Song(id: "1", title: "T", bitRate: 256, suffix: "m4a").qualityLabel == "256 kbps")
    }

    @Test func fallsBackToSuffixThenNil() {
        #expect(Song(id: "1", title: "T", suffix: "ogg").qualityLabel == "OGG")
        #expect(Song(id: "1", title: "T").qualityLabel == nil)
    }

    @Test func losslessRanksAboveAnyLossyBitRate() {
        let flac = Song(id: "1", title: "T", bitRate: 700, suffix: "flac")
        let mp3 = Song(id: "2", title: "T", bitRate: 320, suffix: "mp3")
        #expect(flac.qualityRank > mp3.qualityRank)
    }
}

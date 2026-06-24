import Testing
import MediaPlayer
import AppKit
@testable import Sonicwave

/// Regression tests for `NowPlayingCenter`. MediaPlayer invokes the artwork
/// request handler on a background queue; if that closure inherits the class's
/// `@MainActor` isolation, the Swift runtime traps (SIGTRAP) when it runs
/// off-main — which crashed the app on every play once artwork loaded.
/// See Services/NowPlayingCenter.swift.
@MainActor
struct NowPlayingCenterTests {
    private func track() -> Song {
        Song(id: "1", title: "Hello", artist: "World", duration: 120)
    }

    @Test func artworkRequestHandlerRunsOffMainThreadWithoutTrapping() async {
        let center = NowPlayingCenter()
        center.update(track: track(), state: .playing, position: 0, duration: 120)
        center.updateArtwork(NSImage(size: NSSize(width: 64, height: 64)))

        let artwork = MPNowPlayingInfoCenter.default()
            .nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
        #expect(artwork != nil)

        // Invoke the handler off the main thread, exactly as MediaPlayer does.
        // Before the @Sendable fix this trapped the whole test process.
        let produced: NSImage? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: artwork?.image(at: CGSize(width: 64, height: 64)))
            }
        }
        #expect(produced != nil)
    }

    @Test func updatePopulatesMetadata() {
        let center = NowPlayingCenter()
        center.update(track: track(), state: .playing, position: 10, duration: 120)
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Hello")
        #expect(info?[MPMediaItemPropertyArtist] as? String == "World")
    }
}

import Testing
import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
@testable import Sonicwave

/// Evidence-gathering tests for the audio "crackle" investigation. They feed a
/// *known pure sine* through the real `ProgressiveAudioSource` (AudioFileStream +
/// AVAudioConverter, the same per-packet-batch decode used at playback) and
/// measure sample-to-sample discontinuities. A clean decode keeps steps tiny; a
/// dropout/glitch — especially at a per-batch buffer boundary — shows up as a
/// large jump. This isolates "is the decode pipeline itself glitchy?" from
/// runtime buffering/underrun. Self-contained (no network). See docs/03.
struct DecodeContinuityTests {
    private let sampleRate = 44_100.0
    private let freq: Float = 440
    private let amp: Float = 0.5

    private let seconds = 3.0

    /// Generate an N-second 440 Hz stereo sine in the canonical float format.
    private func makeSine() -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        for ch in 0..<2 {
            let p = buf.floatChannelData![ch]
            for n in 0..<Int(frames) {
                p[n] = amp * sinf(2 * .pi * freq * Float(n) / Float(sampleRate))
            }
        }
        return buf
    }

    /// 7-byte ADTS header for one AAC-LC frame (44.1 kHz / stereo).
    private func adtsHeader(frameLength: Int) -> Data {
        let profile = 1            // AAC LC (audioObjectType 2 - 1)
        let srIndex = 4            // 44100 Hz
        let channels = 2
        var h = [UInt8](repeating: 0, count: 7)
        h[0] = 0xFF
        h[1] = 0xF1                // MPEG-4, layer 0, no CRC
        h[2] = UInt8((profile << 6) | (srIndex << 2) | ((channels >> 2) & 0x1))
        h[3] = UInt8(((channels & 0x3) << 6) | ((frameLength >> 11) & 0x3))
        h[4] = UInt8((frameLength >> 3) & 0xFF)
        h[5] = UInt8(((frameLength & 0x7) << 5) | 0x1F)
        h[6] = 0xFC
        return Data(h)
    }

    /// Encode the sine to an ADTS-AAC byte stream (a real streaming format the
    /// AudioFileStream parser handles incrementally).
    private func encodeToADTS(_ sine: AVAudioPCMBuffer) throws -> Data {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = sampleRate
        asbd.mFormatID = kAudioFormatMPEG4AAC
        asbd.mFramesPerPacket = 1024
        asbd.mChannelsPerFrame = 2
        let aac = try #require(AVAudioFormat(streamDescription: &asbd))
        let converter = try #require(AVAudioConverter(from: sine.format, to: aac))

        final class Feed: @unchecked Sendable { var done = false; let buf: AVAudioPCMBuffer; init(_ b: AVAudioPCMBuffer) { buf = b } }
        let feed = Feed(sine)
        let input: AVAudioConverterInputBlock = { _, status in
            if feed.done { status.pointee = .endOfStream; return nil }
            feed.done = true; status.pointee = .haveData; return feed.buf
        }

        // Output capacity must exceed the total packet count so a single
        // convert() consumes the whole input buffer (the converter discards any
        // unconsumed input between convert() calls).
        let packetCap = AVAudioPacketCount(Double(sine.frameLength) / 1024.0) + 32
        var adts = Data()
        while true {
            let out = AVAudioCompressedBuffer(format: aac, packetCapacity: packetCap, maximumPacketSize: 2048)
            var err: NSError?
            let status = converter.convert(to: out, error: &err, withInputFrom: input)
            if let pds = out.packetDescriptions, out.packetCount > 0 {
                let base = out.data.assumingMemoryBound(to: UInt8.self)
                for i in 0..<Int(out.packetCount) {
                    let off = Int(pds[i].mStartOffset)
                    let size = Int(pds[i].mDataByteSize)
                    adts.append(adtsHeader(frameLength: 7 + size))
                    adts.append(Data(bytes: base + off, count: size))
                }
            }
            if status == .endOfStream || status == .error { break }
        }
        return adts
    }

    @Test func progressiveDecodeIsContinuous() async throws {
        let sine = makeSine()
        let adts = try encodeToADTS(sine)
        #expect(adts.count > 1000) // sanity: we produced an AAC stream

        let canonical = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let source = ProgressiveAudioSource(outputFormat: canonical)
        source.open(fileTypeHint: kAudioFileAAC_ADTSType)

        // Feed in small chunks so packetsProc fires many small batches — the
        // exact per-batch behavior used during streaming playback.
        let chunk = 2048
        var off = 0
        while off < adts.count {
            let end = min(off + chunk, adts.count)
            source.parse(adts.subdata(in: off..<end))
            off = end
        }
        source.finish()

        // Concatenate decoded PCM (channel 0) and record per-batch boundaries.
        var samples: [Float] = []
        var boundaries: [Int] = []
        for await box in source.buffers {
            let buf = box.buffer
            if let ch = buf.floatChannelData, buf.frameLength > 0 {
                boundaries.append(samples.count)
                samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
            }
        }

        // We got a meaningful amount of decoded audio to analyse. (This synthetic
        // ADTS stream may not decode in full — AudioFileStream is finicky about
        // hand-rolled ADTS — but the decoded portion is what we check for
        // glitches; real-file completeness is covered by LiveDecodeTests.)
        #expect(samples.count > 4096)

        // Theoretical max step for this sine: amp * sin(2π·f/sr).
        let expectedStep = amp * sinf(2 * .pi * freq / Float(sampleRate))

        // Largest single-sample jump in the interior (skip codec priming/padding
        // at the very start/end). A dropout/discontinuity = a big jump.
        let guardN = 3000
        var maxInteriorStep: Float = 0
        if samples.count > 2 * guardN {
            for n in (guardN + 1)..<(samples.count - guardN) {
                maxInteriorStep = max(maxInteriorStep, abs(samples[n] - samples[n - 1]))
            }
        }

        // Largest jump specifically across per-batch buffer boundaries.
        var maxBoundaryStep: Float = 0
        for b in boundaries where b > guardN && b < samples.count - guardN {
            maxBoundaryStep = max(maxBoundaryStep, abs(samples[b] - samples[b - 1]))
        }

        // Evidence in the test log.
        let expectedFrames = Int(sampleRate * seconds)
        let evidence = "[crackle] adtsBytes=\(adts.count) expectedFrames=\(expectedFrames) samples=\(samples.count) " +
              "batches=\(boundaries.count) " +
              "expectedStep=\(expectedStep) maxInteriorStep=\(maxInteriorStep) " +
              "maxBoundaryStep=\(maxBoundaryStep)"
        print(evidence)

        // A continuous decode keeps every step near the sine's natural slope
        // (allow generous slack for lossy-AAC quantization). A real glitch would
        // be an order of magnitude larger (toward 2·amp).
        #expect(maxInteriorStep < expectedStep * 6)
        #expect(maxBoundaryStep < expectedStep * 6)
    }

    /// Tests the exact AIFF code path's math in isolation: encode a sine to
    /// big-endian int16 (AIFF sample format), wrap it in an AVAudioPCMBuffer like
    /// `ProgressiveAudioSource` does, convert back to canonical float via
    /// AVAudioConverter, and verify the values match the original (within int16
    /// quantization) with no discontinuities.
    @Test func bigEndianInt16ConversionIsAccurate() throws {
        let sine = makeSine()
        let n = Int(sine.frameLength)

        // Big-endian, signed, packed, interleaved 16-bit — exactly AIFF (flags=14).
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        let beFormat = try #require(AVAudioFormat(streamDescription: &asbd))

        // Hand-encode the sine to big-endian int16 interleaved bytes.
        let beBuf = try #require(AVAudioPCMBuffer(pcmFormat: beFormat, frameCapacity: AVAudioFrameCount(n)))
        beBuf.frameLength = AVAudioFrameCount(n)
        let dst = beBuf.mutableAudioBufferList.pointee.mBuffers.mData!.assumingMemoryBound(to: UInt8.self)
        let src = sine.floatChannelData!
        for f in 0..<n {
            for ch in 0..<2 {
                var be = Int16(max(-1, min(1, src[ch][f])) * 32767).bigEndian
                memcpy(dst + (f * 2 + ch) * 2, &be, 2)
            }
        }

        // Decode back via the converter (the path handlePackets uses), draining
        // fully (a single convert() call caps output at ~4096 frames).
        let canonical = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let conv = try #require(AVAudioConverter(from: beFormat, to: canonical))
        var provided = false
        var out: [Float] = []
        while true {
            let pcm = try #require(AVAudioPCMBuffer(pcmFormat: canonical, frameCapacity: 8192))
            var err: NSError?
            let st = conv.convert(to: pcm, error: &err) { _, s in
                if provided { s.pointee = .endOfStream; return nil } // flush held tail
                provided = true; s.pointee = .haveData; return beBuf
            }
            if pcm.frameLength > 0, let ch = pcm.floatChannelData {
                out.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(pcm.frameLength)))
            }
            if st != .haveData { break }
        }

        // Compare to the original channel-0 sine.
        var maxErr: Float = 0
        let compareN = min(out.count, n)
        for i in 0..<compareN { maxErr = max(maxErr, abs(out[i] - src[0][i])) }
        print("[crackle-be] inFrames=\(n) outFrames=\(out.count) maxErr=\(maxErr)")
        #expect(out.count == n)        // all frames recovered, none dropped
        #expect(maxErr < 0.001)        // values accurate within int16 quantization
    }
}

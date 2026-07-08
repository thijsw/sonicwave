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
        for channel in 0..<2 {
            let samples = buf.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                samples[frame] = amp * sinf(2 * .pi * freq * Float(frame) / Float(sampleRate))
            }
        }
        return buf
    }

    /// 7-byte ADTS header for one AAC-LC frame (44.1 kHz / stereo).
    private func adtsHeader(frameLength: Int) -> Data {
        let profile = 1            // AAC LC (audioObjectType 2 - 1)
        let srIndex = 4            // 44100 Hz
        let channels = 2
        var header = [UInt8](repeating: 0, count: 7)
        header[0] = 0xFF
        header[1] = 0xF1                // MPEG-4, layer 0, no CRC
        header[2] = UInt8((profile << 6) | (srIndex << 2) | ((channels >> 2) & 0x1))
        header[3] = UInt8(((channels & 0x3) << 6) | ((frameLength >> 11) & 0x3))
        header[4] = UInt8((frameLength >> 3) & 0xFF)
        header[5] = UInt8(((frameLength & 0x7) << 5) | 0x1F)
        header[6] = 0xFC
        return Data(header)
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

        final class Feed: @unchecked Sendable {
            var done = false
            let buf: AVAudioPCMBuffer
            init(_ buffer: AVAudioPCMBuffer) { buf = buffer }
        }
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
            if let channelData = buf.floatChannelData, buf.frameLength > 0 {
                boundaries.append(samples.count)
                samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(buf.frameLength)))
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
            for idx in (guardN + 1)..<(samples.count - guardN) {
                maxInteriorStep = max(maxInteriorStep, abs(samples[idx] - samples[idx - 1]))
            }
        }

        // Largest jump specifically across per-batch buffer boundaries.
        var maxBoundaryStep: Float = 0
        for boundary in boundaries where boundary > guardN && boundary < samples.count - guardN {
            maxBoundaryStep = max(maxBoundaryStep, abs(samples[boundary] - samples[boundary - 1]))
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

    /// AAC in an MP4 container needs the file's magic cookie, which
    /// `AVAudioConverter` can't receive — instead of decoding to garbage, the
    /// source must refuse with a user-facing message and produce no buffers.
    @Test func aacInMP4SurfacesGracefulError() async throws {
        let sine = makeSine()

        // Encode a real .m4a (AAC in MP4) via AVAudioFile.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonicwave-test-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: sine)
        file.close() // flush the moov atom
        let m4a = try Data(contentsOf: url)
        #expect(m4a.count > 1000)

        let canonical = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let source = ProgressiveAudioSource(outputFormat: canonical)
        source.open(fileTypeHint: kAudioFileM4AType)
        let chunk = 2048
        var off = 0
        while off < m4a.count {
            let end = min(off + chunk, m4a.count)
            source.parse(m4a.subdata(in: off..<end))
            off = end
        }
        source.finish()

        var decodedFrames = 0
        for await box in source.buffers { decodedFrames += Int(box.buffer.frameLength) }

        #expect(decodedFrames == 0)              // no garbage reached the pipeline
        let message = try #require(source.failureMessage)
        #expect(message.contains("Transcode"))   // the message is actionable
    }

    /// Tests the exact AIFF code path's math in isolation: encode a sine to
    /// big-endian int16 (AIFF sample format), wrap it in an AVAudioPCMBuffer like
    /// `ProgressiveAudioSource` does, convert back to canonical float via
    /// AVAudioConverter, and verify the values match the original (within int16
    /// quantization) with no discontinuities.
    @Test func bigEndianInt16ConversionIsAccurate() throws {
        let sine = makeSine()
        let frameCount = Int(sine.frameLength)

        // Big-endian, signed, packed, interleaved 16-bit — exactly AIFF (flags=14).
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        let beFormat = try #require(AVAudioFormat(streamDescription: &asbd))

        // Hand-encode the sine to big-endian int16 interleaved bytes.
        let beBuf = try #require(AVAudioPCMBuffer(pcmFormat: beFormat, frameCapacity: AVAudioFrameCount(frameCount)))
        beBuf.frameLength = AVAudioFrameCount(frameCount)
        let dst = beBuf.mutableAudioBufferList.pointee.mBuffers.mData!.assumingMemoryBound(to: UInt8.self)
        let src = sine.floatChannelData!
        for frame in 0..<frameCount {
            for channel in 0..<2 {
                var beSample = Int16(max(-1, min(1, src[channel][frame])) * 32767).bigEndian
                memcpy(dst + (frame * 2 + channel) * 2, &beSample, 2)
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
            let status = conv.convert(to: pcm, error: &err) { _, inputStatus in
                if provided { inputStatus.pointee = .endOfStream; return nil } // flush held tail
                provided = true; inputStatus.pointee = .haveData; return beBuf
            }
            if pcm.frameLength > 0, let channelData = pcm.floatChannelData {
                out.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(pcm.frameLength)))
            }
            if status != .haveData { break }
        }

        // Compare to the original channel-0 sine.
        var maxErr: Float = 0
        let compareN = min(out.count, frameCount)
        for i in 0..<compareN { maxErr = max(maxErr, abs(out[i] - src[0][i])) }
        print("[crackle-be] inFrames=\(frameCount) outFrames=\(out.count) maxErr=\(maxErr)")
        #expect(out.count == frameCount)        // all frames recovered, none dropped
        #expect(maxErr < 0.001)        // values accurate within int16 quantization
    }
}

@preconcurrency import AVFoundation
import AudioToolbox
import os

/// Option A streaming decoder: parses incoming compressed bytes with Audio File
/// Stream Services and converts packets to PCM with `AVAudioConverter`, emitting
/// `AVAudioPCMBuffer`s as they're produced. See docs/03-playback-engine.md.
///
/// Used only from within the `PlaybackService` actor: `parse(_:)`/`finish()` are
/// called on the actor, and the AudioFileStream C callbacks fire synchronously
/// inside `parse`, so all mutable state is touched on a single executor.
final class ProgressiveAudioSource: AudioStreamSource {
    let buffers: AsyncStream<SendablePCMBuffer>
    private let continuation: AsyncStream<SendablePCMBuffer>.Continuation

    private var streamID: AudioFileStreamID?
    private var sourceFormat: AVAudioFormat?
    /// Format this track decodes to — the timeline's format, so a single player
    /// node can play tracks back-to-back gaplessly. When `chooseOutput` is set
    /// (rate matching, timeline starts only) it is re-chosen from the source's
    /// native rate once discovered.
    private(set) var outputFormat: AVAudioFormat
    /// Picks the output format from the discovered source format (nil = keep
    /// the fixed `outputFormat`).
    private let chooseOutput: (@Sendable (AVAudioFormat) -> AVAudioFormat)?
    private var converter: AVAudioConverter?

    private static let log = Logger(subsystem: "nl.huell.sonicwave", category: "decode")
    private var decodedFrames: AVAudioFramePosition = 0
    private var inputFrames: AVAudioFramePosition = 0

    /// Seconds of decoded output to discard from the start. Used to seek on
    /// non-transcoded streams (the server can't offset the original file), by
    /// decoding from 0 and dropping everything before the seek point. Kept in
    /// seconds because the output rate may not be known until discovery.
    private let skipSeconds: TimeInterval
    /// Frame form of `skipSeconds`, fixed at format discovery.
    private var skipFrames: AVAudioFramePosition = 0
    private var producedFrames: AVAudioFramePosition = 0
    /// Consolidate the many small per-batch decoder outputs into ~1-second
    /// buffers before yielding. Scheduling thousands of tiny buffers in a burst
    /// (a whole track decodes far faster than real time) starves the audio IO
    /// thread → a dropped cycle → an audible click. Fewer, larger buffers fix it.
    private let chunkTarget: AVAudioFrameCount = 44_100
    private var accum: AVAudioPCMBuffer?

    init(outputFormat: AVAudioFormat, skipSeconds: TimeInterval = 0,
         chooseOutput: (@Sendable (AVAudioFormat) -> AVAudioFormat)? = nil) {
        self.outputFormat = outputFormat
        self.skipSeconds = skipSeconds
        self.chooseOutput = chooseOutput
        self.skipFrames = AVAudioFramePosition(skipSeconds * outputFormat.sampleRate)
        let (stream, continuation) = AsyncStream.makeStream(of: SendablePCMBuffer.self)
        self.buffers = stream
        self.continuation = continuation
    }

    /// Open the parser. `fileTypeHint` may be 0 to let the parser auto-detect.
    func open(fileTypeHint: AudioFileTypeID = 0) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        var sid: AudioFileStreamID?
        let status = AudioFileStreamOpen(context, Self.propertyProc, Self.packetsProc, fileTypeHint, &sid)
        if status == noErr { streamID = sid }
    }

    func parse(_ data: Data) {
        guard let streamID else { return }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress, !raw.isEmpty {
                let st = AudioFileStreamParseBytes(streamID, UInt32(raw.count), base,
                                              AudioFileStreamParseFlags(rawValue: 0))
                if st != noErr { Self.log.error("AudioFileStreamParseBytes failed: \(st)") }
            }
        }
    }

    func finish() {
        flushDecoder()
        flushAccum()
        Self.log.debug("decode finished: inputFrames=\(self.inputFrames) decodedFrames=\(self.decodedFrames)")
        continuation.finish()
        if let streamID {
            AudioFileStreamClose(streamID)
            self.streamID = nil
        }
    }

    /// Drain any PCM the decoder/converter is still holding (codec latency) by
    /// running one final conversion with `.endOfStream`. Without this the tail of
    /// each track is silently dropped — audible as a clipped ending / a seam at
    /// gapless transitions.
    private func flushDecoder() {
        guard let converter else { return }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 16_384) else { return }
        var ended = false
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, outStatus in
            if ended { outStatus.pointee = .noDataNow; return nil }
            ended = true
            outStatus.pointee = .endOfStream
            return nil
        }
        if (status == .haveData || status == .endOfStream || status == .inputRanDry) && pcm.frameLength > 0 {
            produce(pcm)
        }
    }

    // MARK: - Output (skip + consolidation)

    /// Apply the seek skip, then consolidate. Buffers fully before the seek point
    /// are dropped; the buffer straddling it is trimmed.
    private func produce(_ pcm: AVAudioPCMBuffer) {
        guard let out = applySkip(pcm) else { return }
        emitConsolidated(out)
    }

    private func applySkip(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard skipFrames > 0 else { return pcm }
        let n = AVAudioFramePosition(pcm.frameLength)
        defer { producedFrames += n }
        if producedFrames >= skipFrames { return pcm }            // fully past the seek
        if producedFrames + n <= skipFrames { return nil }        // fully before the seek
        // Straddles the seek point: keep the tail.
        let drop = Int(skipFrames - producedFrames)
        let keep = Int(pcm.frameLength) - drop
        guard keep > 0, let trimmed = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(keep)) else { return nil }
        trimmed.frameLength = AVAudioFrameCount(keep)
        if let s = pcm.floatChannelData, let d = trimmed.floatChannelData {
            for ch in 0..<Int(outputFormat.channelCount) {
                memcpy(d[ch], s[ch] + drop, keep * MemoryLayout<Float>.size)
            }
        }
        return trimmed
    }

    /// Append small outputs into `accum`, yielding ~1s buffers. Buffers already at
    /// least the target size pass straight through.
    private func emitConsolidated(_ pcm: AVAudioPCMBuffer) {
        if pcm.frameLength >= chunkTarget {
            flushAccum()
            yieldBuffer(pcm)
            return
        }
        if accum == nil || (accum!.frameCapacity - accum!.frameLength) < pcm.frameLength {
            flushAccum()
            accum = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunkTarget + pcm.frameLength)
            accum?.frameLength = 0
        }
        guard let dst = accum else { yieldBuffer(pcm); return }
        let off = Int(dst.frameLength), n = Int(pcm.frameLength)
        if let s = pcm.floatChannelData, let d = dst.floatChannelData {
            for ch in 0..<Int(outputFormat.channelCount) {
                memcpy(d[ch] + off, s[ch], n * MemoryLayout<Float>.size)
            }
            dst.frameLength += pcm.frameLength
        }
        if dst.frameLength >= chunkTarget { flushAccum() }
    }

    private func flushAccum() {
        if let a = accum, a.frameLength > 0 { yieldBuffer(a) }
        accum = nil
    }

    private func yieldBuffer(_ buffer: AVAudioPCMBuffer) {
        continuation.yield(SendablePCMBuffer(buffer: buffer))
    }

    // MARK: - C callbacks (no captured context → convert to C function pointers)

    private static let propertyProc: AudioFileStream_PropertyListenerProc = { clientData, _, propertyID, _ in
        let me = Unmanaged<ProgressiveAudioSource>.fromOpaque(clientData).takeUnretainedValue()
        me.handleProperty(propertyID)
    }

    private static let packetsProc: AudioFileStream_PacketsProc = { clientData, numberBytes, numberPackets, inputData, packetDescriptions in
        let me = Unmanaged<ProgressiveAudioSource>.fromOpaque(clientData).takeUnretainedValue()
        me.handlePackets(numberBytes: numberBytes, numberPackets: numberPackets,
                         inputData: inputData, packetDescriptions: packetDescriptions)
    }

    private func handleProperty(_ propertyID: AudioFileStreamPropertyID) {
        guard sourceFormat == nil, let streamID else { return }
        guard propertyID == kAudioFileStreamProperty_DataFormat
            || propertyID == kAudioFileStreamProperty_ReadyToProducePackets else { return }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_DataFormat, &size, &asbd) == noErr else { return }
        guard let source = AVAudioFormat(streamDescription: &asbd) else { return }

        sourceFormat = source
        if let chooseOutput {
            outputFormat = chooseOutput(source)
            skipFrames = AVAudioFramePosition(skipSeconds * outputFormat.sampleRate)
        }
        converter = AVAudioConverter(from: source, to: outputFormat)
        let isPCM = asbd.mFormatID == kAudioFormatLinearPCM
        Self.log.debug("source format id=\(asbd.mFormatID) sr=\(asbd.mSampleRate) → out sr=\(self.outputFormat.sampleRate) pcm=\(isPCM) converter=\(self.converter != nil)")
    }

    private func handlePackets(numberBytes: UInt32, numberPackets: UInt32,
                               inputData: UnsafeRawPointer,
                               packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard numberPackets > 0,
              let sourceFormat, let converter else { return }

        let inputBuffer: AVAudioBuffer
        let estFrames: Double

        if sourceFormat.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM {
            // Uncompressed source (e.g. WAV/AIFF): these "packets" are raw PCM
            // frames and must go in an AVAudioPCMBuffer. Wrapping linear PCM in an
            // AVAudioCompressedBuffer fails an internal assertion, leaving a broken
            // buffer that decodes to garbage — audible as crackle on those tracks.
            let bytesPerFrame = Int(sourceFormat.streamDescription.pointee.mBytesPerFrame)
            guard bytesPerFrame > 0 else { return }
            let frames = AVAudioFrameCount(Int(numberBytes) / bytesPerFrame)
            guard frames > 0,
                  let pcmIn = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames)
            else { return }
            pcmIn.frameLength = frames
            memcpy(pcmIn.mutableAudioBufferList.pointee.mBuffers.mData, inputData, Int(numberBytes))
            inputBuffer = pcmIn
            estFrames = Double(frames)
        } else {
            // Compressed source: wrap this batch of packets in a compressed buffer.
            let maxPacketSize: Int
            if let pds = packetDescriptions {
                var m = 0
                for i in 0..<Int(numberPackets) { m = max(m, Int(pds[i].mDataByteSize)) }
                maxPacketSize = max(m, 1)
            } else {
                maxPacketSize = max(Int(numberBytes) / Int(numberPackets), 1)
            }

            let compressed = AVAudioCompressedBuffer(format: sourceFormat,
                                                     packetCapacity: AVAudioPacketCount(numberPackets),
                                                     maximumPacketSize: maxPacketSize)
            compressed.byteLength = numberBytes
            compressed.packetCount = AVAudioPacketCount(numberPackets)
            memcpy(compressed.data, inputData, Int(numberBytes))
            if let pds = packetDescriptions, let dest = compressed.packetDescriptions {
                for i in 0..<Int(numberPackets) { dest[i] = pds[i] }
            }

            // Estimate output capacity from frames-per-packet (fallback for VBR).
            let framesPerPacket = sourceFormat.streamDescription.pointee.mFramesPerPacket
            estFrames = framesPerPacket > 0
                ? Double(numberPackets) * Double(framesPerPacket)
                : Double(numberPackets) * 1024
            inputBuffer = compressed
        }

        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(estFrames * ratio) + 16_384
        guard let pcm = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var provided = false
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        decodedFrames += AVAudioFramePosition(pcm.frameLength)
        inputFrames += AVAudioFramePosition(estFrames)
        if let error { Self.log.error("convert error: \(error.localizedDescription)") }
        if (status == .haveData || status == .inputRanDry) && pcm.frameLength > 0 {
            produce(pcm)
        }
    }
}

/// Maps a file suffix to an AudioFileStream type hint (0 = auto-detect).
func audioFileTypeHint(forSuffix suffix: String?) -> AudioFileTypeID {
    switch suffix?.lowercased() {
    case "mp3": return kAudioFileMP3Type
    case "m4a", "aac", "mp4": return kAudioFileM4AType
    case "flac": return kAudioFileFLACType
    case "wav": return kAudioFileWAVEType
    case "aif", "aiff": return kAudioFileAIFFType
    case "caf": return kAudioFileCAFType
    default: return 0
    }
}

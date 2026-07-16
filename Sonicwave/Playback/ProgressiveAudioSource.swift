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
/// One-shot flag for `AVAudioConverter` input blocks. The block type is
/// `@Sendable` in the SDK, but `convert(to:error:withInputFrom:)` invokes it
/// synchronously on the calling thread, so unchecked access is safe.
private final class InputFlag: @unchecked Sendable {
    var raised = false
}

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

    /// Set when the stream turns out to be undecodable — a user-facing message
    /// (why + what to do). `AVAudioConverter` has no magic-cookie API, so
    /// cookie-dependent containers (AAC/ALAC in MP4/M4A) would decode to
    /// garbage; they're refused at format discovery instead. Checked by
    /// `PlaybackService` to stop the transfer and surface the failure.
    private(set) var failureMessage: String?

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
                let status = AudioFileStreamParseBytes(streamID, UInt32(raw.count), base,
                                                       AudioFileStreamParseFlags(rawValue: 0))
                if status != noErr { Self.log.error("AudioFileStreamParseBytes failed: \(status)") }
            }
        }
        // Conversion happens HERE, after ParseBytes returned — constructing
        // AVFoundation buffers inside the packets callback silently corrupts
        // the FLAC parser (every subsequent ParseBytes returns 'wht?' after a
        // handful of frames; MP3 happens to tolerate it). Repro + fix proof
        // in PROGRESS 2026-07-16. The callback only copies raw bytes.
        drainPendingPackets()
    }

    func finish() {
        drainPendingPackets()
        flushDecoder()
        flushAccum()
        // The whole stream came and went without a decodable format (a
        // container the parser can't stream, or corrupt data): report it
        // rather than ending in silent, unexplained non-playback.
        if sourceFormat == nil, failureMessage == nil {
            failureMessage = "This track's format can't be streamed directly. " + Self.transcodeHint
        }
        Self.log.debug("decode finished: inputFrames=\(self.inputFrames) decodedFrames=\(self.decodedFrames)")
        continuation.finish()
        if let streamID {
            AudioFileStreamClose(streamID)
            self.streamID = nil
        }
    }

    private static let transcodeHint =
        "Turn on \"Transcode on the server\" in Settings → Playback to play it."

    /// Drain any PCM the decoder/converter is still holding (codec latency) by
    /// running one final conversion with `.endOfStream`. Without this the tail of
    /// each track is silently dropped — audible as a clipped ending / a seam at
    /// gapless transitions.
    private func flushDecoder() {
        guard let converter else { return }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 16_384) else { return }
        let ended = InputFlag()
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, outStatus in
            if ended.raised { outStatus.pointee = .noDataNow; return nil }
            ended.raised = true
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
        let frames = AVAudioFramePosition(pcm.frameLength)
        defer { producedFrames += frames }
        if producedFrames >= skipFrames { return pcm }            // fully past the seek
        if producedFrames + frames <= skipFrames { return nil }   // fully before the seek
        // Straddles the seek point: keep the tail.
        let drop = Int(skipFrames - producedFrames)
        let keep = Int(pcm.frameLength) - drop
        guard keep > 0,
              let trimmed = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(keep))
        else { return nil }
        trimmed.frameLength = AVAudioFrameCount(keep)
        if let src = pcm.floatChannelData, let dst = trimmed.floatChannelData {
            for channel in 0..<Int(outputFormat.channelCount) {
                memcpy(dst[channel], src[channel] + drop, keep * MemoryLayout<Float>.size)
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
        let off = Int(dst.frameLength), frameCount = Int(pcm.frameLength)
        if let src = pcm.floatChannelData, let dstData = dst.floatChannelData {
            for channel in 0..<Int(outputFormat.channelCount) {
                memcpy(dstData[channel] + off, src[channel], frameCount * MemoryLayout<Float>.size)
            }
            dst.frameLength += pcm.frameLength
        }
        if dst.frameLength >= chunkTarget { flushAccum() }
    }

    private func flushAccum() {
        if let pending = accum, pending.frameLength > 0 { yieldBuffer(pending) }
        accum = nil
    }

    private func yieldBuffer(_ buffer: AVAudioPCMBuffer) {
        continuation.yield(SendablePCMBuffer(buffer: buffer))
    }

    // MARK: - C callbacks (no captured context → convert to C function pointers)

    private static let propertyProc: AudioFileStream_PropertyListenerProc = { clientData, _, propertyID, _ in
        let source = Unmanaged<ProgressiveAudioSource>.fromOpaque(clientData).takeUnretainedValue()
        source.handleProperty(propertyID)
    }

    private static let packetsProc: AudioFileStream_PacketsProc = { context, bytes, packets, data, descs in
        let source = Unmanaged<ProgressiveAudioSource>.fromOpaque(context).takeUnretainedValue()
        source.handlePackets(numberBytes: bytes, numberPackets: packets,
                             inputData: data, packetDescriptions: descs)
    }

    private func handleProperty(_ propertyID: AudioFileStreamPropertyID) {
        guard sourceFormat == nil, let streamID else { return }
        guard propertyID == kAudioFileStreamProperty_DataFormat
            || propertyID == kAudioFileStreamProperty_ReadyToProducePackets else { return }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_DataFormat,
                                         &size, &asbd) == noErr else { return }
        guard let source = AVAudioFormat(streamDescription: &asbd) else { return }

        // Compressed audio in an MP4/M4A container needs the file's magic
        // cookie handed to the decoder, and `AVAudioConverter` has no cookie
        // API — conversion would emit garbage (audible as loud static).
        // Refuse cleanly: leave `sourceFormat`/`converter` nil so no packets
        // convert, and say why. (ADTS/MP3/FLAC/WAV/AIFF are self-describing.)
        var fileFormat: UInt32 = 0
        var ffSize = UInt32(MemoryLayout<UInt32>.size)
        AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_FileFormat, &ffSize, &fileFormat)
        if [kAudioFileM4AType, kAudioFileMPEG4Type].contains(AudioFileTypeID(fileFormat)),
           asbd.mFormatID != kAudioFormatLinearPCM {
            failureMessage = "This track is compressed audio (AAC/ALAC) in an MP4 container, "
                + "which can't be streamed directly yet. " + Self.transcodeHint
            Self.log.error("refusing cookie-dependent container: format id \(asbd.mFormatID)")
            return
        }

        sourceFormat = source
        if let chooseOutput {
            outputFormat = chooseOutput(source)
            skipFrames = AVAudioFramePosition(skipSeconds * outputFormat.sampleRate)
        }
        converter = AVAudioConverter(from: source, to: outputFormat)
        let isPCM = asbd.mFormatID == kAudioFormatLinearPCM
        Self.log.debug("""
        source format id=\(asbd.mFormatID) sr=\(asbd.mSampleRate) → \
        out sr=\(self.outputFormat.sampleRate) pcm=\(isPCM) converter=\(self.converter != nil)
        """)
    }

    /// One packets-callback batch, copied verbatim (plain memory only — no
    /// AVFoundation objects may be constructed inside the callback).
    private struct PendingPackets {
        var bytes: Data
        var descriptions: [AudioStreamPacketDescription]
        var packetCount: UInt32
    }
    private var pendingPackets: [PendingPackets] = []

}

// MARK: - Input building & conversion (outside the parser callbacks)

private extension ProgressiveAudioSource {
    /// Uncompressed source (e.g. WAV/AIFF): these "packets" are raw PCM frames
    /// and must go in an AVAudioPCMBuffer. Wrapping linear PCM in an
    /// AVAudioCompressedBuffer fails an internal assertion, leaving a broken
    /// buffer that decodes to garbage — audible as crackle on those tracks.
    private func makePCMInput(_ batch: PendingPackets,
                              sourceFormat: AVAudioFormat) -> (buffer: AVAudioBuffer, estFrames: Double)? {
        let bytesPerFrame = Int(sourceFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        let frames = AVAudioFrameCount(batch.bytes.count / bytesPerFrame)
        guard frames > 0,
              let pcmIn = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames)
        else { return nil }
        pcmIn.frameLength = frames
        batch.bytes.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(pcmIn.mutableAudioBufferList.pointee.mBuffers.mData, base, raw.count)
            }
        }
        return (pcmIn, Double(frames))
    }

    /// Compressed source: wrap a batch of packets in a compressed buffer.
    private func makeCompressedInput(_ batch: PendingPackets,
                                     sourceFormat: AVAudioFormat) -> (buffer: AVAudioBuffer, estFrames: Double) {
        // Capacity must cover the whole batch: packetCapacity × maxPacketSize
        // ≥ byteLength, so take the larger of the biggest packet and the
        // ceiling average.
        let largest = batch.descriptions.map { Int($0.mDataByteSize) }.max() ?? 0
        let ceilingAverage = (batch.bytes.count + Int(batch.packetCount) - 1) / Int(batch.packetCount)
        let maxPacketSize = max(largest, max(ceilingAverage, 1))

        let compressed = AVAudioCompressedBuffer(format: sourceFormat,
                                                 packetCapacity: AVAudioPacketCount(batch.packetCount),
                                                 maximumPacketSize: maxPacketSize)
        compressed.byteLength = UInt32(batch.bytes.count)
        compressed.packetCount = AVAudioPacketCount(batch.packetCount)
        batch.bytes.withUnsafeBytes { raw in
            if let base = raw.baseAddress { memcpy(compressed.data, base, raw.count) }
        }
        if let dest = compressed.packetDescriptions {
            for (i, desc) in batch.descriptions.enumerated() { dest[i] = desc }
        }

        // Estimate output capacity from frames-per-packet (fallback for VBR).
        let framesPerPacket = sourceFormat.streamDescription.pointee.mFramesPerPacket
        let estFrames = framesPerPacket > 0
            ? Double(batch.packetCount) * Double(framesPerPacket)
            : Double(batch.packetCount) * 1024
        return (compressed, estFrames)
    }

    /// Called from the packets callback, mid-ParseBytes: copy and get out.
    private func handlePackets(numberBytes: UInt32, numberPackets: UInt32,
                               inputData: UnsafeRawPointer,
                               packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard numberPackets > 0 else { return }
        let descriptions = packetDescriptions.map {
            Array(UnsafeBufferPointer(start: $0, count: Int(numberPackets)))
        } ?? []
        pendingPackets.append(PendingPackets(
            bytes: Data(bytes: inputData, count: Int(numberBytes)),
            descriptions: descriptions,
            packetCount: numberPackets))
    }

    private func drainPendingPackets() {
        guard !pendingPackets.isEmpty else { return }
        let batches = pendingPackets
        pendingPackets.removeAll()
        for batch in batches { convert(batch) }
    }

    private func convert(_ batch: PendingPackets) {
        guard let sourceFormat, let converter else { return }

        let input: (buffer: AVAudioBuffer, estFrames: Double)
        if sourceFormat.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM {
            guard let pcmInput = makePCMInput(batch, sourceFormat: sourceFormat) else { return }
            input = pcmInput
        } else {
            input = makeCompressedInput(batch, sourceFormat: sourceFormat)
        }
        let (inputBuffer, estFrames) = input

        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(estFrames * ratio) + 16_384
        guard let pcm = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        let provided = InputFlag()
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, outStatus in
            if provided.raised {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided.raised = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        decodedFrames += AVAudioFramePosition(pcm.frameLength)
        inputFrames += AVAudioFramePosition(estFrames)
        if let error { Self.log.error("convert error: \(error.localizedDescription)") }
        if (status == .haveData || status == .inputRanDry) && pcm.frameLength > 0 {
            produce(pcm)
        }
    }}

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

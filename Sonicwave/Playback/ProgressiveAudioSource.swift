@preconcurrency import AVFoundation
import AudioToolbox

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
    /// Fixed canonical format all tracks decode to, so a single player node can
    /// play them back-to-back gaplessly (and sample-rate changes are resampled).
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
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
                _ = AudioFileStreamParseBytes(streamID, UInt32(raw.count), base,
                                              AudioFileStreamParseFlags(rawValue: 0))
            }
        }
    }

    func finish() {
        continuation.finish()
        if let streamID {
            AudioFileStreamClose(streamID)
            self.streamID = nil
        }
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
        converter = AVAudioConverter(from: source, to: outputFormat)
    }

    private func handlePackets(numberBytes: UInt32, numberPackets: UInt32,
                               inputData: UnsafeRawPointer,
                               packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        guard numberPackets > 0,
              let sourceFormat, let converter else { return }

        // Build a compressed buffer holding this batch of packets.
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

        // Estimate the output capacity from frames-per-packet (fallback for VBR).
        let framesPerPacket = sourceFormat.streamDescription.pointee.mFramesPerPacket
        let estFrames = framesPerPacket > 0
            ? Double(numberPackets) * Double(framesPerPacket)
            : Double(numberPackets) * 1024
        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(estFrames * ratio) + 4096
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
            return compressed
        }

        if (status == .haveData || status == .inputRanDry) && pcm.frameLength > 0 {
            continuation.yield(SendablePCMBuffer(buffer: pcm))
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

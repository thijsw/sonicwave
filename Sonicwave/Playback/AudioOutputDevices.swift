import Foundation
import CoreAudio

/// A selectable audio output device. `uid` is the stable identifier persisted
/// across launches (the numeric `id` can change on reboot/replug).
struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    /// Core Audio transport-type AirPlay. Note: an AirPlay receiver only
    /// exists as a Core Audio device while the system is connected to it
    /// (first connection happens via Control Center — there is no public
    /// sender API); once present, it's pickable and routable like any other.
    let isAirPlay: Bool
}

/// Fires `onChange` whenever the system's audio device list changes (device
/// connected / disconnected). Callback arrives on a private queue.
final class AudioDeviceListObserver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "nl.huell.sonicwave.audio-devices")
    private let block: AudioObjectPropertyListenerBlock
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init(onChange: @escaping @Sendable () -> Void) {
        block = { _, _ in onChange() }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }
}

/// Thin Core Audio wrapper to enumerate output-capable devices and resolve the
/// system default. See docs/03-playback-engine.md (output device selection).
enum AudioOutputDevices {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    /// All devices that can play audio out. Core Audio's transient private
    /// aggregates (created when the default device switches mid-render) are
    /// excluded — they're plumbing, not user-selectable outputs.
    static func all() -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutput).compactMap(device(for:))
            .filter { !$0.uid.hasPrefix("CADefaultDeviceAggregate") }
    }

    /// The current system default output device id, if any.
    static func defaultOutputID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &dev) == noErr else { return nil }
        return dev
    }

    /// Resolve a persisted UID back to the live device id.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        all().first { $0.uid == uid }?.id
    }

    // MARK: - Hardware sample rate (bit-perfect rate matching)

    /// The device's current nominal (hardware) sample rate.
    static func nominalSampleRate(of id: AudioDeviceID) -> Double? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rate = Double(0)
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate) == noErr else { return nil }
        return rate
    }

    /// Set the device's nominal sample rate. The switch is asynchronous on the
    /// hardware side and fires configuration-change notifications.
    @discardableResult
    static func setNominalSampleRate(_ rate: Double, on id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = rate
        return AudioObjectSetPropertyData(id, &addr, 0, nil,
                                          UInt32(MemoryLayout<Double>.size), &value) == noErr
    }

    /// The closest hardware rate the device supports for `target`: the exact
    /// rate when available, else the nearest supported one (ties go up).
    static func bestSupportedRate(for target: Double, on id: AudioDeviceID) -> Double? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ranges = [AudioValueRange](repeating: AudioValueRange(),
                                       count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ranges) == noErr else { return nil }

        var best: Double?
        for range in ranges {
            // A continuous range containing the target supports it exactly;
            // discrete rates arrive as ranges with min == max.
            if (range.mMinimum...range.mMaximum).contains(target) { return target }
            for candidate in [range.mMinimum, range.mMaximum] {
                if best == nil
                    || abs(candidate - target) < abs(best! - target)
                    || (abs(candidate - target) == abs(best! - target) && candidate > best!) {
                    best = candidate
                }
            }
        }
        return best
    }

    // MARK: - Per-device queries

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func device(for id: AudioDeviceID) -> AudioDevice? {
        guard let name = string(id, kAudioObjectPropertyName),
              let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return AudioDevice(id: id, uid: uid, name: name,
                           isAirPlay: transportType(id) == kAudioDeviceTransportTypeAirPlay)
    }

    /// The device's transport (built-in / USB / AirPlay / …).
    static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport) == noErr else { return 0 }
        return transport
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfString: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfString) == noErr, let cfString else { return nil }
        return cfString.takeRetainedValue() as String
    }
}

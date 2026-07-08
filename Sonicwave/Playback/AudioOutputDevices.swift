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
    private var address = AudioOutputDevices.address(kAudioHardwarePropertyDevices)

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
        let ids: [AudioDeviceID] = readArray(system, kAudioHardwarePropertyDevices) ?? []
        return ids.filter(hasOutput).compactMap(device(for:))
            .filter { !$0.uid.hasPrefix("CADefaultDeviceAggregate") }
    }

    /// The current system default output device id, if any.
    static func defaultOutputID() -> AudioDeviceID? {
        read(system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioDeviceID.self)
    }

    /// Resolve a persisted UID back to the live device id.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        all().first { $0.uid == uid }?.id
    }

    // MARK: - Hardware sample rate (bit-perfect rate matching)

    /// The device's current nominal (hardware) sample rate.
    static func nominalSampleRate(of id: AudioDeviceID) -> Double? {
        read(id, kAudioDevicePropertyNominalSampleRate, as: Double.self)
    }

    /// Set the device's nominal sample rate. The switch is asynchronous on the
    /// hardware side and fires configuration-change notifications.
    @discardableResult
    static func setNominalSampleRate(_ rate: Double, on id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var value = rate
        return AudioObjectSetPropertyData(id, &addr, 0, nil,
                                          UInt32(MemoryLayout<Double>.size), &value) == noErr
    }

    /// The closest hardware rate the device supports for `target`: the exact
    /// rate when available, else the nearest supported one (ties go up).
    static func bestSupportedRate(for target: Double, on id: AudioDeviceID) -> Double? {
        guard let ranges: [AudioValueRange] =
                readArray(id, kAudioDevicePropertyAvailableNominalSampleRates) else { return nil }

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
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
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
        read(id, kAudioDevicePropertyTransportType, as: UInt32.self) ?? 0
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        guard let cfString = read(id, selector, as: Unmanaged<CFString>?.self) ?? nil else { return nil }
        return cfString.takeRetainedValue() as String
    }

    // MARK: - Property plumbing

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Read a fixed-size property value. `T` must be a trivial (C-layout) type.
    private static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                as type: T.Type) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let raw = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return nil }
        return raw.pointee
    }

    /// Read a variable-length array property. `T` must be a trivial type.
    private static func readArray<T>(_ id: AudioObjectID,
                                     _ selector: AudioObjectPropertySelector) -> [T]? {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        let count = Int(size) / MemoryLayout<T>.stride
        let raw = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return nil }
        return Array(UnsafeBufferPointer(start: raw, count: count))
    }
}

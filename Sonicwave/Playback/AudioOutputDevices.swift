import Foundation
import CoreAudio

/// A selectable audio output device. `uid` is the stable identifier persisted
/// across launches (the numeric `id` can change on reboot/replug).
struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
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
        return AudioDevice(id: id, uid: uid, name: name)
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cf) == noErr, let cf else { return nil }
        return cf.takeRetainedValue() as String
    }
}

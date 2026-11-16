import CoreAudio
import Foundation
import Newtv1Core

struct SystemAudioDevice: Identifiable {
    let id: String
    let objectID: AudioObjectID
    let name: String
}

/// Uses the selected Core Audio device, never an inferred app or an arbitrary script.
enum SystemAudio {
    static func address(_ selector: AudioObjectPropertySelector, _ direction: AudioDirection? = nil, channel: UInt32 = 0) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: direction == nil ? kAudioObjectPropertyScopeGlobal : direction == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, mElement: channel)
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector), size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    static func devices(_ direction: AudioDirection) -> [SystemAudioDevice] {
        var property = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!) }
        guard result == noErr else { return [] }
        return ids.compactMap { id in
            var stream = address(kAudioDevicePropertyStreams, direction), bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &stream, 0, nil, &bytes) == noErr, bytes > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return SystemAudioDevice(id: uid, objectID: id, name: string(id, kAudioObjectPropertyName) ?? "Audio device")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func selected(_ direction: AudioDirection) -> AudioObjectID {
        var property = address(direction == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioObjectID = 0, size = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &id)
        return id
    }
    static func choose(_ direction: AudioDirection, query: String) throws -> String {
        let all = devices(direction)
        let uid = try AudioDeviceMatch.resolve(query, devices: all.map { AudioDeviceIdentity(id: $0.id, name: $0.name) })
        guard let device = all.first(where: { $0.id == uid }) else { throw Newtv1Failure("That audio device disconnected.") }
        var property = address(direction == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.objectID
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id) == noErr,
              selected(direction) == id else { throw Newtv1Failure("The Mac did not accept the audio device change.") }
        return "Verified audio \(direction.rawValue): \(device.name)."
    }
    static func level(_ id: AudioObjectID, _ direction: AudioDirection) -> Float? {
        var values: [Float] = []
        for channel: UInt32 in [0, 1, 2] {
            var property = address(kAudioDevicePropertyVolumeScalar, direction, channel: channel)
            var value: Float = 0, size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr, value.isFinite {
                if channel == 0 { return max(0, min(1, value)) }
                values.append(value)
            }
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }
    static func setLevel(_ id: AudioObjectID, _ direction: AudioDirection, value: Float) throws {
        guard value.isFinite, (0...1).contains(value) else { throw Newtv1Failure("Audio level must be 0–100 percent.") }
        var writable: [UInt32] = []
        for channel: UInt32 in [0, 1, 2] {
            var property = address(kAudioDevicePropertyVolumeScalar, direction, channel: channel), settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(id, &property, &settable) == noErr, settable.boolValue {
                writable.append(channel); if channel == 0 { break }
            }
        }
        guard !writable.isEmpty else { throw Newtv1Failure("This audio device does not expose an adjustable \(direction.rawValue) level.") }
        for channel in writable {
            var property = address(kAudioDevicePropertyVolumeScalar, direction, channel: channel), amount = value
            guard AudioObjectSetPropertyData(id, &property, 0, nil, UInt32(MemoryLayout<Float>.size), &amount) == noErr else { throw Newtv1Failure("The audio device declined a level change. Check Sound settings before retrying.") }
        }
        guard let actual = level(id, direction), abs(actual - value) < 0.025 else { throw Newtv1Failure("The requested audio level was not confirmed by the device.") }
    }
    static func muted(_ id: AudioObjectID, _ direction: AudioDirection) -> Bool? {
        var property = address(kAudioDevicePropertyMute, direction), value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
    static func supportsMute(_ id: AudioObjectID, _ direction: AudioDirection) -> Bool {
        var property = address(kAudioDevicePropertyMute, direction), settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(id, &property, &settable) == noErr && settable.boolValue
    }
    static func setMute(_ id: AudioObjectID, _ direction: AudioDirection, value: Bool) throws {
        var property = address(kAudioDevicePropertyMute, direction), amount: UInt32 = value ? 1 : 0
        guard AudioObjectSetPropertyData(id, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &amount) == noErr,
              muted(id, direction) == value else { throw Newtv1Failure("The audio device did not confirm the mute change.") }
    }
}

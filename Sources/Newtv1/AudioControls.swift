import CoreAudio
import SwiftUI
import AppKit

@MainActor
final class AudioControls: ObservableObject {
    struct Device: Identifiable { let id: AudioObjectID; let name: String }
    @Published private(set) var outputs: [Device] = []
    @Published private(set) var selected: AudioObjectID = 0
    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var adjustable = false
    @Published private(set) var message = ""
    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, channel: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress { AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: channel) }
    func refresh() {
        var defaultAddress = address(kAudioHardwarePropertyDefaultOutputDevice); var device: AudioObjectID = 0; var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &size, &device) == noErr else { return }
        selected = device
        var devicesAddress = address(kAudioHardwarePropertyDevices); size = 0
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &size) == noErr {
            var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            let result = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &size, $0.baseAddress!) }
            if result == noErr {
                outputs = ids.compactMap { id in
                    var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput); var streamSize: UInt32 = 0
                    guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
                    var nameAddress = address(kAudioObjectPropertyName); var name: Unmanaged<CFString>?; var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                    _ = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
                    return Device(id: id, name: name?.takeUnretainedValue() as String? ?? "Audio output")
                }
            }
        }
        var total: Float = 0; var channels = 0
        for channel: UInt32 in [0,1,2] {
            var property = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: channel)
            var value: Float = 0; var valueSize = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(device, &property, 0, nil, &valueSize, &value) == noErr { total += value; channels += 1; if channel == 0 { break } }
        }
        adjustable = channels > 0; volume = channels > 0 ? total / Float(channels) : 0
        var muteAddress = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput); var mute: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        muted = AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &mute) == noErr && mute != 0
    }
    func choose(_ id: AudioObjectID) {
        guard outputs.contains(where: { $0.id == id }) else { return }
        var property = address(kAudioHardwarePropertyDefaultOutputDevice); var value = id
        let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
        message = result == noErr ? "" : "Could not switch output."; refresh()
    }
    func setVolume(_ newValue: Float) {
        guard newValue.isFinite else { return }
        var value = max(0,min(1,newValue)); var success = false
        for channel: UInt32 in [0,1,2] {
            var property = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: channel)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(selected, &property, &settable) == noErr, settable.boolValue else { continue }
            if AudioObjectSetPropertyData(selected, &property, 0, nil, UInt32(MemoryLayout<Float>.size), &value) == noErr { success = true; if channel == 0 { break } }
        }
        message = success ? "" : "This output does not support system volume adjustment."; refresh()
    }
    func toggleMute() {
        var property = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput); var value: UInt32 = muted ? 0 : 1
        message = AudioObjectSetPropertyData(selected, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr ? "" : "This output does not support system mute."
        refresh()
    }
}
struct AudioModule: View {
    @ObservedObject var audio: AudioControls
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Output", selection: Binding(get: { audio.selected }, set: { audio.choose($0) })) { ForEach(audio.outputs) { Text($0.name).tag($0.id) } }.labelsHidden().controlSize(.small)
            HStack { Button { audio.toggleMute() } label: { Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }.buttonStyle(.plain).help("Toggle output mute"); Slider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }), in: 0...1).disabled(!audio.adjustable); Text("\(Int(audio.volume * 100))%").font(.system(size: 10)).monospacedDigit() }
            if !audio.message.isEmpty { Text(audio.message).font(.system(size: 10)).foregroundStyle(.orange) }
        }.onAppear { audio.refresh() }
    }
}

import AppKit
import ApplicationServices
import CoreWLAN
import CoreAudio
import IOKit.pwr_mgt
import Newtv1Core

@MainActor
final class SystemControls: ObservableObject {
    @Published private(set) var wifiOn: Bool?
    @Published private(set) var darkAppearance = false
    @Published private(set) var inputs: [SystemAudioDevice] = []
    @Published private(set) var outputs: [SystemAudioDevice] = []
    @Published private(set) var inputID = ""
    @Published private(set) var outputID = ""
    @Published private(set) var microphoneLevel: Float?
    @Published private(set) var microphoneMuted = false
    @Published private(set) var awakeUntil: Date?
    private var assertion: IOPMAssertionID = 0
    private var restoredLevels: [String: Float] = [:]
    private var lastResult: (SystemCommand, String)?

    func refresh() {
        wifiOn = CWWiFiClient.shared().interface().map { $0.powerOn() }
        darkAppearance = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        inputs = SystemAudio.devices(.input); outputs = SystemAudio.devices(.output)
        let input = SystemAudio.selected(.input), output = SystemAudio.selected(.output)
        inputID = inputs.first { $0.objectID == input }?.id ?? ""
        outputID = outputs.first { $0.objectID == output }?.id ?? ""
        microphoneLevel = SystemAudio.level(input, .input)
        microphoneMuted = SystemAudio.muted(input, .input) == true || microphoneLevel == 0
        if let awakeUntil, awakeUntil <= Date() { endKeepAwake() }
    }

    func perform(_ command: SystemCommand, runner: ProcessRunner) async throws -> String {
        try command.validate()
        try Task.checkCancellation()
        lastResult = nil
        defer { refresh() }
        let result: String
        switch command {
        case .wifi(let enabled):
            guard let interface = CWWiFiClient.shared().interface() else { throw Newtv1Failure("No Wi-Fi interface is available on this Mac.") }
            try interface.setPower(enabled)
            guard interface.powerOn() == enabled else { throw Newtv1Failure("Wi-Fi power did not change. Check your network policy in System Settings.") }
            result = enabled ? "Verified Wi-Fi is on. Network reconnection is managed by macOS." : "Verified Wi-Fi is off."
        case .appearance(let appearance):
            let expression = appearance == .toggle ? "not dark mode" : appearance == .dark ? "true" : "false"
            let script = "tell application \"System Events\" to tell appearance preferences\nset dark mode to \(expression)\nreturn dark mode\nend tell"
            let value = try await runner.run("/usr/bin/osascript", ["-e", script])
            guard ["true", "false"].contains(value.lowercased()) else { throw Newtv1Failure("Appearance change could not be confirmed.") }
            result = "Verified " + (value.lowercased() == "true" ? "dark" : "light") + " system appearance."
        case .dockAutoHide(let enabled):
            let script = "tell application \"System Events\" to tell dock preferences\nset autohide to \(enabled ? "true" : "false")\nreturn autohide\nend tell"
            let value = try await runner.run("/usr/bin/osascript", ["-e", script])
            guard value.lowercased() == (enabled ? "true" : "false") else { throw Newtv1Failure("Dock preference change could not be confirmed.") }
            result = "Verified Dock automatic hiding is " + (enabled ? "on." : "off.")
        case .inputVolume(let amount):
            try SystemAudio.setLevel(SystemAudio.selected(.input), .input, value: Float(amount) / 100)
            result = "Verified microphone input volume: \(amount)%."
        case .inputMute(let muted):
            let id = SystemAudio.selected(.input)
            guard let uid = SystemAudio.string(id, kAudioDevicePropertyDeviceUID) else { throw Newtv1Failure("No default microphone is available.") }
            if SystemAudio.supportsMute(id, .input) {
                try SystemAudio.setMute(id, .input, value: muted)
                result = muted ? "Verified microphone mute is on. Use the System Controls page to unmute." : "Verified microphone hardware mute is off."
            } else if muted {
                guard let previous = SystemAudio.level(id, .input) else { throw Newtv1Failure("This microphone exposes neither mute nor adjustable input gain.") }
                if previous > 0 { restoredLevels[uid] = previous }
                try SystemAudio.setLevel(id, .input, value: 0)
                result = "Verified microphone input gain is zero. Use System Controls to restore it."
            } else {
                guard let previous = restoredLevels[uid] else {
                    throw Newtv1Failure("This microphone has no hardware mute. Set its input volume in System Controls; Newt has no previous level to restore.")
                }
                try SystemAudio.setLevel(id, .input, value: previous)
                restoredLevels.removeValue(forKey: uid)
                result = "Verified microphone input gain was restored."
            }
        case .volumeChange(let amount):
            let id = SystemAudio.selected(.output)
            guard let level = SystemAudio.level(id, .output) else { throw Newtv1Failure("This output does not expose a system volume control.") }
            let next = max(0, min(1, level + Float(amount) / 100))
            try SystemAudio.setLevel(id, .output, value: next)
            result = "Verified output volume: \(Int(round(next * 100)))%."
        case .audioDevice(let direction, let query): result = try SystemAudio.choose(direction, query: query)
        case .keepAwake(let minutes):
            var next: IOPMAssertionID = 0
            let status = IOPMAssertionCreateWithDescription(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                "Newtv1 timed keep-awake" as CFString, "User-requested \(minutes)-minute session" as CFString,
                nil, nil, Double(minutes * 60), kIOPMAssertionTimeoutActionRelease as CFString, &next)
            guard status == kIOReturnSuccess else { throw Newtv1Failure("macOS declined the keep-awake session.") }
            endKeepAwake()
            assertion = next; awakeUntil = Date().addingTimeInterval(Double(minutes * 60))
            result = "Keep-awake assertion created for \(minutes) minutes. Display sleep, manual sleep, closing the lid and system policies still apply."
        case .allowSleep:
            endKeepAwake(); result = "Newtv1’s keep-awake session ended. Other apps’ power settings are unchanged."
        case .displaySleep:
            _ = try await runner.run("/usr/bin/pmset", ["displaysleepnow"])
            result = "Display sleep requested. Move the pointer or press a key to wake it."
        case .brightness(let steps):
            for _ in 0..<steps.magnitude { try Task.checkCancellation(); try sendMediaKey(steps > 0 ? 2 : 3); try await Task.sleep(nanoseconds: 70_000_000) }
            result = "Brightness key steps sent. The target display must support macOS brightness keys; inspect its level."
        case .media(let key):
            try sendMediaKey(key == .playPause ? 16 : key == .next ? 17 : 18)
            result = "Media key sent to macOS’s active player. Inspect the player to confirm playback."
        case .settings(let pane):
            let identifiers: [SettingsPane: String] = [.displays: "com.apple.Displays-Settings.extension", .sound: "com.apple.Sound-Settings.extension",
                .wifi: "com.apple.wifi-settings-extension", .bluetooth: "com.apple.BluetoothSettings", .battery: "com.apple.Battery-Settings.extension",
                .keyboard: "com.apple.Keyboard-Settings.extension", .mouse: "com.apple.Mouse-Settings.extension", .trackpad: "com.apple.Trackpad-Settings.extension", .appearance: "com.apple.Appearance-Settings.extension"]
            guard let identifier = identifiers[pane], let url = URL(string: "x-apple.systempreferences:" + identifier), NSWorkspace.shared.open(url) else { throw Newtv1Failure("Could not open this settings pane.") }
            result = "Opened \(pane.title) settings."
        }
        try Task.checkCancellation()
        lastResult = (command, result)
        return result
    }

    func verification(_ command: SystemCommand) throws -> String {
        guard let (previous, result) = lastResult, previous == command else { throw Newtv1Failure("No matching system-control result is available.") }
        return result
    }

    func endKeepAwake() {
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        awakeUntil = nil
    }
    deinit { if assertion != 0 { IOPMAssertionRelease(assertion) } }

    private func sendMediaKey(_ key: Int) throws {
        guard AXIsProcessTrusted() else { throw Newtv1Failure("Enable Mac control access to send brightness and media keys.") }
        // Public HID auxiliary-key event format: key type in the high word, down/up in the low word.
        for state in [0xA, 0xB] {
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)), timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | (state << 8), data2: 0)?.cgEvent else { throw Newtv1Failure("Could not create a system key event.") }
            event.setIntegerValueField(.eventSourceUserData, value: 0x4E545631)
            event.post(tap: .cghidEventTap)
        }
    }
}

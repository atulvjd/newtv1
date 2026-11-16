import Foundation

public enum SystemAppearance: String, Codable, Sendable { case dark, light, toggle }
public enum AudioDirection: String, Codable, Sendable { case input, output }
public enum MediaKey: String, Codable, Sendable { case playPause, next, previous }
public enum SettingsPane: String, Codable, Sendable, CaseIterable {
    case displays, sound, wifi, bluetooth, battery, keyboard, mouse, trackpad, appearance
    public var title: String { self == .wifi ? "Wi-Fi" : self == .bluetooth ? "Bluetooth" : rawValue.capitalized }
}

/// Typed system operations shared by direct commands, reviewed AI plans and recovery history.
public enum SystemCommand: Equatable, Codable, Sendable {
    case appearance(SystemAppearance), wifi(Bool), dockAutoHide(Bool)
    case inputVolume(Int), inputMute(Bool), volumeChange(Int)
    case audioDevice(AudioDirection, String)
    case keepAwake(Int), allowSleep, displaySleep
    case brightness(Int), media(MediaKey), settings(SettingsPane)

    public var needsConfirmation: Bool {
        switch self { case .wifi(false), .displaySleep: return true; default: return false }
    }
    public var requiresAccessibility: Bool {
        switch self { case .brightness, .media: return true; default: return false }
    }
    public var summary: String {
        switch self {
        case .appearance(let style): return style == .toggle ? "Toggle light / dark appearance" : "Use \(style.rawValue) appearance"
        case .wifi(let enabled): return enabled ? "Turn Wi-Fi on" : "Turn Wi-Fi off · disconnect wireless networking"
        case .dockAutoHide(let enabled): return enabled ? "Automatically hide the Dock" : "Keep the Dock visible"
        case .inputVolume(let amount): return "Set microphone input volume to \(amount)%"
        case .inputMute(let muted): return muted ? "Mute the system microphone" : "Unmute the system microphone"
        case .volumeChange(let amount): return "\(amount > 0 ? "Increase" : "Decrease") volume by \(amount.magnitude)%"
        case .audioDevice(let direction, let name): return "Use \(name) for audio \(direction.rawValue)"
        case .keepAwake(let minutes): return "Keep Mac awake for \(minutes) minutes · display may still sleep"
        case .allowSleep: return "End Newtv1’s keep-awake session"
        case .displaySleep: return "Sleep the display now"
        case .brightness(let steps): return "Send \(steps.magnitude) brightness \(steps > 0 ? "up" : "down") key steps"
        case .media(let key): return key == .playPause ? "Play / pause active media" : key == .next ? "Next media track" : "Previous media track"
        case .settings(let pane): return "Open \(pane.title) settings"
        }
    }

    public func validate() throws {
        switch self {
        case .inputVolume(let value): guard (0...100).contains(value) else { throw CommandError.invalid("Microphone volume must be between 0 and 100.") }
        case .volumeChange(let value): guard value != 0, (-25...25).contains(value) else { throw CommandError.invalid("Volume changes must be 1–25 percent.") }
        case .brightness(let steps): guard steps != 0, (-10...10).contains(steps) else { throw CommandError.invalid("Brightness changes must be 1–10 steps.") }
        case .keepAwake(let minutes): guard (1...180).contains(minutes) else { throw CommandError.invalid("Keep-awake sessions must be 1–180 minutes.") }
        case .audioDevice(_, let name):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw CommandError.invalid("Use the exact audio device name, up to 120 characters.") }
        default: break
        }
    }

    public static let plannerCommands = "dark mode, light mode, toggle appearance, wifi on, wifi off, hide dock, show dock, microphone volume 0-100, mute microphone, unmute microphone, volume up, volume down, audio output DEVICE_NAME, audio input DEVICE_NAME, keep awake for MINUTES minutes (1-180), allow sleep, sleep display, brightness up, brightness down, play pause, next track, previous track, open displays settings, open sound settings, open wifi settings, open bluetooth settings, top left quarter, top right quarter, bottom left quarter, bottom right quarter"

    public static func parse(_ raw: String) throws -> SystemCommand? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        switch lower {
        case "dark mode", "enable dark mode", "turn on dark mode": return .appearance(.dark)
        case "light mode", "disable dark mode", "turn off dark mode": return .appearance(.light)
        case "toggle appearance", "toggle dark mode": return .appearance(.toggle)
        case "wifi on", "wi-fi on", "turn on wifi", "turn on wi-fi", "enable wifi": return .wifi(true)
        case "wifi off", "wi-fi off", "turn off wifi", "turn off wi-fi", "disable wifi": return .wifi(false)
        case "hide dock", "auto hide dock": return .dockAutoHide(true)
        case "show dock", "keep dock visible": return .dockAutoHide(false)
        case "mute microphone", "mute mic": return .inputMute(true)
        case "unmute microphone", "unmute mic": return .inputMute(false)
        case "volume up", "increase volume", "turn volume up": return .volumeChange(10)
        case "volume down", "decrease volume", "turn volume down": return .volumeChange(-10)
        case "brightness up", "increase brightness": return .brightness(1)
        case "brightness down", "decrease brightness": return .brightness(-1)
        case "play pause", "play pause media", "toggle playback": return .media(.playPause)
        case "next track", "next song", "skip track": return .media(.next)
        case "previous track", "previous song": return .media(.previous)
        case "allow sleep", "stop keeping awake", "end keep awake": return .allowSleep
        case "sleep display", "sleep the display", "turn off display": return .displaySleep
        default: break
        }
        for pane in SettingsPane.allCases {
            let names = pane == .wifi ? ["wifi", "wi-fi"] : [pane.rawValue]
            if names.contains(where: { lower == "open \($0) settings" || lower == "\($0) settings" }) { return .settings(pane) }
        }
        for (prefix, direction) in [("audio output ", AudioDirection.output), ("set audio output to ", .output), ("audio input ", .input), ("set audio input to ", .input)] where lower.hasPrefix(prefix) {
            let result = SystemCommand.audioDevice(direction, String(text.dropFirst(prefix.count)))
            try result.validate(); return result
        }
        for prefix in ["microphone volume ", "set microphone volume to ", "input volume "] where lower.hasPrefix(prefix) {
            let value = String(lower.dropFirst(prefix.count)).replacingOccurrences(of: " percent", with: "").replacingOccurrences(of: "%", with: "")
            guard let number = CommandParser.number(value) else { throw CommandError.invalid("Try “microphone volume fifty percent”.") }
            let result = SystemCommand.inputVolume(number); try result.validate(); return result
        }
        for prefix in ["keep awake for ", "stay awake for "] where lower.hasPrefix(prefix) {
            let value = String(lower.dropFirst(prefix.count))
            guard value.hasSuffix(" minutes") || value.hasSuffix(" minute") else { throw CommandError.invalid("Specify minutes, e.g. “keep awake for thirty minutes”.") }
            let number = value.replacingOccurrences(of: " minutes", with: "").replacingOccurrences(of: " minute", with: "")
            guard let minutes = CommandParser.number(number) else { throw CommandError.invalid("Specify 1–180 minutes.") }
            let result = SystemCommand.keepAwake(minutes); try result.validate(); return result
        }
        for (prefix, sign) in [("brightness up ", 1), ("brightness down ", -1), ("volume up ", 1), ("volume down ", -1)] where lower.hasPrefix(prefix) {
            let value = String(lower.dropFirst(prefix.count)).replacingOccurrences(of: " steps", with: "").replacingOccurrences(of: " step", with: "").replacingOccurrences(of: " percent", with: "").replacingOccurrences(of: "%", with: "")
            guard let amount = CommandParser.number(value), amount > 0 else { throw CommandError.invalid("Specify a positive step amount.") }
            let result: SystemCommand = prefix.hasPrefix("brightness") ? .brightness(sign * amount) : .volumeChange(sign * amount)
            try result.validate(); return result
        }
        return nil
    }
}

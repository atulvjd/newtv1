import Foundation
import CoreGraphics

public enum NotchStyle: String, Codable, CaseIterable { case attached, floating }
public enum NotchFinish: String, Codable, CaseIterable { case black, gradient, glass }
public enum NotchExpansionLayout: String, Codable, CaseIterable { case horizontal, vertical }
public enum NotchSection: String, Codable, CaseIterable, Identifiable {
    case voice, media, shortcuts, workflows, activity, clock, timer, notes, calendar, downloads, shelf, system, camera, clipboard, inbox, routines, audio
    public var id: String { rawValue }
    public var title: String { self == .media ? "Now Playing" : rawValue.capitalized }
    public var icon: String {
        switch self {
        case .voice: return "waveform"
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .downloads: return "arrow.down.circle"
        case .shelf: return "tray"
        case .system: return "gauge.with.dots.needle.50percent"
        case .camera: return "camera"
        case .clipboard: return "doc.on.clipboard"
        case .inbox: return "bell"
        case .routines: return "calendar.badge.clock"
        case .audio: return "speaker.wave.2"
        case .shortcuts: return "bolt"
        case .workflows: return "square.stack.3d.up"
        case .activity: return "clock.arrow.circlepath"
        case .clock: return "clock"
        case .timer: return "timer"
        case .notes: return "note.text"
        }
    }
}
public enum NotchWingAction: String, Codable, CaseIterable {
    case microphone, expand, brain, commandCenter, showNumbers, screenshot, clock
    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .expand: return "Expand / pin"
        case .brain: return "Brain"
        case .commandCenter: return "Command center"
        case .showNumbers: return "Number controls"
        case .screenshot: return "Screenshot"
        case .clock: return "Clock"
        }
    }
    public var icon: String {
        switch self {
        case .microphone: return "mic.fill"
        case .expand: return "sparkle"
        case .brain: return "sparkles"
        case .commandCenter: return "square.grid.2x2"
        case .showNumbers: return "number.square"
        case .screenshot: return "camera.viewfinder"
        case .clock: return "clock"
        }
    }
}

public struct NotchShortcut: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var icon: String
    public var command: String
    public init(id: UUID = UUID(), title: String, icon: String = "bolt", command: String) {
        self.id = id; self.title = title; self.icon = icon; self.command = command
    }
}

public struct NotchConfiguration: Codable, Equatable {
    public var schemaVersion = 1
    public var style: NotchStyle = .attached
    public var finish: NotchFinish = .black
    public var expansionLayout: NotchExpansionLayout = .horizontal
    public var fullWidthExpansion = true
    public var horizontalHeight = 160.0
    public var accentHex = "C9F76E"
    public var expandedWidth = 460.0
    public var contentHeight = 340.0
    public var wingWidth = 52.0
    public var cornerRadius = 22.0
    public var opacity = 1.0
    public var borderOpacity = 0.14
    public var floatingGap = 12.0
    public var horizontalOffset = 0.0
    public var displayID = "automatic"
    public var hoverToExpand = true
    public var hoverDelay = 0.15
    public var collapseDelay = 0.65
    public var expandOnListening = true
    public var expandOnExecution = true
    public var expandOnError = true
    public var pinnedOnLaunch = false
    public var animations = true
    public var showWaveform = true
    public var compactRows = false
    public var leftWing: NotchWingAction = .microphone
    public var rightWing: NotchWingAction = .expand
    public var sectionOrder = NotchSection.allCases
    public var hiddenSections: [NotchSection] = [.clock, .timer, .notes, .calendar, .downloads, .shelf, .system, .camera, .clipboard, .inbox, .routines, .audio]
    public var shortcuts = [
        NotchShortcut(title: "Numbers", icon: "number.square", command: "show numbers"),
        NotchShortcut(title: "Left half", icon: "rectangle.lefthalf.inset.filled", command: "left half"),
        NotchShortcut(title: "Screenshot", icon: "camera.viewfinder", command: "take a screenshot")
    ]

    public init() {}
    public var visibleSections: [NotchSection] { sectionOrder.filter { !hiddenSections.contains($0) } }
    public var hasHardwareHeader: Bool { style == .attached }

    public func normalized() -> Self {
        var copy = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double { value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback }
        copy.expandedWidth = clamp(expandedWidth, 360...3200, 1200)
        copy.horizontalHeight = clamp(horizontalHeight, 120...260, 160)
        copy.contentHeight = clamp(contentHeight, 220...700, 340)
        copy.wingWidth = clamp(wingWidth, 32...110, 52)
        copy.cornerRadius = clamp(cornerRadius, 6...40, 22)
        copy.opacity = clamp(opacity, 0.65...1, 1)
        copy.borderOpacity = clamp(borderOpacity, 0...0.65, 0.14)
        copy.floatingGap = clamp(floatingGap, 0...120, 12)
        copy.horizontalOffset = clamp(horizontalOffset, -1000...1000, 0)
        copy.hoverDelay = clamp(hoverDelay, 0...1.5, 0.15)
        copy.collapseDelay = clamp(collapseDelay, 0.15...5, 0.65)
        let hex = accentHex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        copy.accentHex = hex.count == 6 && hex.allSatisfy(\.isHexDigit) ? hex : "C9F76E"
        copy.sectionOrder = []
        for section in sectionOrder + NotchSection.allCases where !copy.sectionOrder.contains(section) { copy.sectionOrder.append(section) }
        copy.hiddenSections = Array(Set(hiddenSections)).sorted { $0.rawValue < $1.rawValue }
        var ids = Set<UUID>()
        copy.shortcuts = shortcuts.prefix(8).compactMap { shortcut in
            guard ids.insert(shortcut.id).inserted, !shortcut.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !shortcut.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, shortcut.command.count <= 4000 else { return nil }
            var item = shortcut
            item.title = String(item.title.prefix(40)); item.icon = String(item.icon.prefix(70))
            return item
        }
        copy.displayID = String(displayID.prefix(100))
        return copy
    }

    public static func profile(_ data: Data) throws -> Self {
        guard data.count <= 128_000 else { throw CommandError.invalid("Notch profiles must be smaller than 128 KB.") }
        // Older profiles had a stacked layout only. Preserve their settings while
        // adopting the new horizontal expansion default.
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CommandError.invalid("Invalid notch profile.") }
        if object["expansionLayout"] == nil { object["expansionLayout"] = "horizontal" }
        if object["fullWidthExpansion"] == nil { object["fullWidthExpansion"] = true }
        if object["horizontalHeight"] == nil { object["horizontalHeight"] = 160 }
        if var order = object["sectionOrder"] as? [String], !order.contains("media") {
            order.insert("media", at: order.firstIndex(of: "voice").map { $0 + 1 } ?? 0)
            object["sectionOrder"] = order
        }
        let oldOrder = Set((object["sectionOrder"] as? [String]) ?? [])
        if var hidden = object["hiddenSections"] as? [String] {
            for section in ["calendar", "downloads", "shelf", "system", "camera", "clipboard", "inbox", "routines", "audio"] where !oldOrder.contains(section) && !hidden.contains(section) { hidden.append(section) }
            object["hiddenSections"] = hidden
        }
        let value = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
        guard value.schemaVersion == 1 else { throw CommandError.invalid("This notch profile version is not supported.") }
        return value.normalized()
    }

    public static func preset(_ name: String) -> Self {
        var config = Self()
        switch name {
        case "Minimal":
            config.expandedWidth = 380; config.contentHeight = 230
            config.hiddenSections = [.shortcuts, .workflows, .activity, .clock, .timer, .notes]
            config.compactRows = true; config.borderOpacity = 0
        case "Studio":
            config.expandedWidth = 560; config.contentHeight = 480
            config.accentHex = "B8A2FF"; config.finish = .gradient
            config.hiddenSections = [.clock]; config.pinnedOnLaunch = true
        case "Focus":
            config.accentHex = "79D5FF"; config.contentHeight = 350
            config.hiddenSections = [.shortcuts, .workflows, .activity, .notes]
            config.hoverToExpand = false; config.expandOnExecution = false
        case "Island":
            config.style = .floating; config.finish = .glass; config.accentHex = "FFB989"
            config.expandedWidth = 440; config.contentHeight = 360
            config.hiddenSections = [.workflows, .activity, .notes]
        default: break
        }
        return config.normalized()
    }
}

public struct NotchGeometry {
    public static let horizontalControlsHeight = 54.0
    public let frame: CGRect
    public let headerHeight: CGFloat
    public let cutoutWidth: CGFloat

    public static func calculate(screen: CGRect, hardwareWidth: CGFloat, hardwareHeight: CGFloat, hardwareCenter: CGFloat? = nil, expanded: Bool, configuration: NotchConfiguration) -> Self {
        let config = configuration.normalized()
        let attached = config.style == .attached
        let cutout = attached ? max(0, hardwareWidth) : 0
        let header: CGFloat = attached ? max(32, hardwareHeight) : 32
        let restingWidth = attached ? cutout + CGFloat(config.wingWidth) * 2 : max(220, CGFloat(config.wingWidth) * 2 + 116)
        let availableWidth = max(1, screen.width - 16)
        let wide = config.expansionLayout == .horizontal
        let expandedWidth = wide && config.fullWidthExpansion ? availableWidth : max(CGFloat(config.expandedWidth), restingWidth)
        let width = min(availableWidth, expanded ? expandedWidth : restingWidth)
        let topOffset = attached ? 0 : max(0, hardwareHeight) + CGFloat(config.floatingGap)
        let bodyHeight = wide ? config.horizontalHeight + horizontalControlsHeight : config.contentHeight
        let height = min(max(1, screen.height - topOffset - 16), expanded ? header + CGFloat(bodyHeight) : header + 8)
        let center = attached ? (hardwareCenter ?? screen.midX) : screen.midX + CGFloat(config.horizontalOffset)
        let x = min(max(center - width / 2, screen.minX + 8), screen.maxX - width - 8)
        return Self(frame: CGRect(x: x, y: screen.maxY - topOffset - height, width: width, height: height), headerHeight: header, cutoutWidth: cutout)
    }
}

import Foundation

public enum IslandActivities {
    /// One primary activity and, at most, one compact secondary activity.
    public static func active(listening: Bool, working: Bool, attention: Bool, playing: Bool, timer: Bool, visible: [NotchSection]) -> [NotchSection] {
        var result: [NotchSection] = []
        if listening || attention { result.append(.voice) }
        if working { result.append(visible.contains(.tasks) ? .tasks : .voice) }
        if timer, visible.contains(.timer) { result.append(.timer) }
        if playing, visible.contains(.media) { result.append(.media) }
        var unique: [NotchSection] = []
        for section in result where !unique.contains(section) { unique.append(section) }
        return unique.isEmpty ? [.voice] : Array(unique.prefix(2))
    }
}

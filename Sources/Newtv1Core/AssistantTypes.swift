import Foundation

public enum AssistantMode: String, Codable, CaseIterable, Identifiable {
    case command, talk, guide, dictate, agent
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var icon: String {
        switch self { case .command: return "command"; case .talk: return "bubble.left.and.bubble.right"; case .guide: return "viewfinder"; case .dictate: return "text.cursor"; case .agent: return "sparkles" }
    }
    public var hint: String {
        switch self {
        case .command: return "Direct, local Mac commands and saved workflows."
        case .talk: return "Ask questions and hear answers. Add screen context only when you choose."
        case .guide: return "Preview a screen, ask for help, then show numbered visual guidance."
        case .dictate: return "Speak directly into the last active app. Newt, stop dictation ends it."
        case .agent: return "Describe a task, review its plan, and follow each step."
        }
    }
}

public struct ConversationTurn: Codable, Equatable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = String(content.prefix(12000)) }
}

public struct ScreenHighlight: Codable, Equatable, Identifiable {
    public var id: String { "\(x)-\(y)-\(label)" }
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let label: String
    public var valid: Bool {
        [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width >= 0.005 && height >= 0.005 && x + width <= 1.00001 && y + height <= 1.00001 && !label.isEmpty && label.count <= 100
    }
}

public struct GuidanceResult: Codable {
    public let answer: String
    public let highlights: [ScreenHighlight]
    public func validated() throws -> Self {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, answer.count <= 16000, highlights.count <= 8, highlights.allSatisfy(\.valid) else { throw CommandError.invalid("Screen guidance returned invalid coordinates. No overlay was drawn.") }
        return self
    }
}

public enum DictationControl {
    public static func shouldStop(_ text: String, custom: String = "") -> Bool {
        guard let command = VoiceCommand.extract(text, requireWakePhrase: true, custom: custom) else { return false }
        return ["stop dictation", "stop dictating", "stop listening"].contains(command.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }
}

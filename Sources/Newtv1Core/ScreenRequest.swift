import Foundation

public enum ScreenRequest: Equatable {
    case preview(String), readText, discard
    public static func parse(_ raw: String) -> ScreenRequest? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        switch lower {
        case "what is on my screen", "what's on my screen", "what’s on my screen", "describe my screen", "explain my screen", "look at my screen", "look at the screen", "show screen context":
            return .preview("Describe what is visible on my screen and help me understand it.")
        case "read my screen", "read the screen", "read screen text", "extract screen text": return .readText
        case "discard screen", "clear screen context", "forget this screen": return .discard
        default: break
        }
        for prefix in ["ask about my screen ", "ask about screen ", "help with my screen "] where text.lowercased().hasPrefix(prefix) {
            let question = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !question.isEmpty, question.count <= 4000 { return .preview(question) }
        }
        return nil
    }
}

public enum ScreenContextPolicy {
    public static let maximumAge: TimeInterval = 120
    public static func isFresh(_ capturedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return age.isFinite && age >= 0 && age <= maximumAge
    }
}

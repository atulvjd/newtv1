import Foundation

public struct TaskSteering: Codable, Equatable {
    public private(set) var revision = 0
    public private(set) var messages: [String] = []
    public init() {}
    public mutating func append(_ text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 8000, messages.count < 8, revision < Int.max else { throw CommandError.invalid("Use 1–8,000 characters and let Newt process the queued follow-ups first.") }
        messages.append(text); revision += 1
    }
    public mutating func consume() -> [String] { defer { messages = [] }; return messages }
}

public enum RoutineExecutionPolicy: String, Codable {
    case review, approvedLocal
    public static func supportsAutomatic(_ actions: [Action]) -> Bool {
        !actions.isEmpty && actions.allSatisfy { action in
            switch action {
            case .openApp, .window, .volume, .mute, .wait: return true
            default: return false
            }
        }
    }
}

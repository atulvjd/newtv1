import Foundation

public struct BrowserTaskMemory: Codable, Equatable {
    public let goal: String
    public let log: [String]
    public let provider: AIProvider
    public init(goal: String, log: [String], provider: AIProvider) {
        self.goal = String(goal.prefix(16000))
        self.log = Array(log.suffix(30)).map { String($0.prefix(3000)) }
        self.provider = provider
    }
}

public enum BrowserRunPolicy: String, CaseIterable, Identifiable {
    case review = "Review every action", inspect = "Continue observation and scrolling"
    public var id: String { rawValue }
    public func allows(_ action: BrowserAction) -> Bool {
        self == .inspect && [.observe, .scroll].contains(action.kind)
    }
}

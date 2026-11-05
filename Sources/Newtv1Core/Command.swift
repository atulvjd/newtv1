import Foundation

public enum Action: Equatable, Sendable {
    case openApp(String), quitApp(String), openURL(String), search(String)
    case typeText(String), shortcut(String), click(String), clickNumber(Int)
    case showNumbers, hideNumbers, scroll(String, Int), window(String)
    case volume(Int), mute(Bool), screenshot, lock, sleep
    case reveal(String), shell(String), workflow(String), wait(Double)

    public var needsConfirmation: Bool {
        switch self {
        case .quitApp, .shell, .lock, .sleep: return true
        default: return false
        }
    }

    public var summary: String {
        switch self {
        case .openApp(let value): return "Open \(value)"
        case .quitApp(let value): return "Quit \(value)"
        case .openURL(let value): return "Go to \(value)"
        case .search(let value): return "Search for \(value)"
        case .typeText(let value): return "Type “\(value)”"
        case .shortcut(let value): return "Press \(value)"
        case .click(let value): return "Click “\(value)”"
        case .clickNumber(let number): return "Click target \(number)"
        case .showNumbers: return "Show numbered controls"
        case .hideNumbers: return "Hide numbered controls"
        case .scroll(let direction, let amount): return "Scroll \(direction) \(amount)"
        case .window(let position): return "Move window: \(position)"
        case .volume(let value): return "Set volume to \(value)%"
        case .mute(let muted): return muted ? "Mute audio" : "Unmute audio"
        case .screenshot: return "Save screenshot to Desktop"
        case .lock: return "Lock screen"
        case .sleep: return "Put Mac to sleep"
        case .reveal(let path): return "Reveal \(path) in Finder"
        case .shell(let command): return "Run shell: \(command)"
        case .workflow(let name): return "Run workflow “\(name)”"
        case .wait(let seconds): return "Wait \(seconds) seconds"
        }
    }
}

public struct CommandPlan: Equatable, Sendable {
    public let transcript: String
    public let actions: [Action]
    public let requiresReview: Bool
    public var needsConfirmation: Bool { requiresReview || actions.contains { $0.needsConfirmation } }
    public init(transcript: String, actions: [Action], requiresReview: Bool = false) {
        self.transcript = transcript
        self.actions = actions
        self.requiresReview = requiresReview
    }
}

public enum CommandError: LocalizedError {
    case empty, unknown(String), invalid(String)
    public var errorDescription: String? {
        switch self {
        case .empty: return "Say or type a command first."
        case .unknown(let text): return "I don’t recognize “\(text)”. Open the command guide for supported phrases."
        case .invalid(let text): return text
        }
    }
}

public struct CommandParser {
    public init() {}

    public func parse(_ input: String) throws -> CommandPlan {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CommandError.empty }
        // Literal commands consume the whole remainder. Never split dictated text or shell code.
        var pieces: [String] = []
        var remaining = text
        while true {
            let literal = ["type ", "write ", "dictate ", "shell ", "search for ", "search "].contains { remaining.lowercased().hasPrefix($0) }
            if !literal, remaining.lowercased().hasSuffix(" then") { throw CommandError.invalid("Add a command after “then”.") }
            if !literal, let separator = remaining.range(of: " then ", options: .caseInsensitive) {
                pieces.append(String(remaining[..<separator.lowerBound]))
                remaining = String(remaining[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else { pieces.append(remaining); break }
        }
        guard pieces.count <= 20 else { throw CommandError.invalid("A command can contain at most 20 steps.") }
        return CommandPlan(transcript: text, actions: try pieces.map(parseAction))
    }

    private func parseAction(_ input: String) throws -> Action {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        func argument(_ prefix: String) -> String? {
            guard lower.hasPrefix(prefix) else { return nil }
            let value = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        switch lower {
        case "show numbers", "show controls": return .showNumbers
        case "hide numbers", "hide controls": return .hideNumbers
        case "screenshot", "take screenshot", "take a screenshot": return .screenshot
        case "mute", "mute audio": return .mute(true)
        case "unmute", "unmute audio": return .mute(false)
        case "lock", "lock screen", "lock my mac": return .lock
        case "sleep", "sleep my mac": return .sleep
        case "maximize", "maximize window", "fill screen": return .window("maximize")
        case "center window": return .window("center")
        case "minimize", "minimize window": return .window("minimize")
        case "left half", "window left", "move window left": return .window("left")
        case "right half", "window right", "move window right": return .window("right")
        case "top half", "window top": return .window("top")
        case "bottom half", "window bottom": return .window("bottom")
        case "copy": return .shortcut("command c")
        case "paste": return .shortcut("command v")
        case "undo": return .shortcut("command z")
        case "redo": return .shortcut("command shift z")
        case "select all": return .shortcut("command a")
        case "new tab": return .shortcut("command t")
        case "close tab": return .shortcut("command w")
        case "next tab": return .shortcut("control tab")
        case "previous tab": return .shortcut("control shift tab")
        case "go back": return .shortcut("command [")
        case "go forward": return .shortcut("command ]")
        case "enter", "return": return .shortcut("return")
        case "escape": return .shortcut("escape")
        default: break
        }
        for prefix in ["type ", "write ", "dictate "] {
            if let value = argument(prefix) { return .typeText(value) }
        }
        if let value = argument("shell ") { return .shell(value) }
        if let value = argument("run ") { return .workflow(value) }
        for prefix in ["search for ", "search "] {
            if let value = argument(prefix) { return .search(value) }
        }
        for prefix in ["open ", "launch ", "switch to "] {
            if let value = argument(prefix) {
                if value.contains("://") || (value.contains(".") && !value.contains(" ") && !value.hasSuffix(".app")) {
                    return .openURL(value)
                }
                return .openApp(value)
            }
        }
        if let value = argument("go to ") { return .openURL(value) }
        if let value = argument("quit ") { return .quitApp(value) }
        if let value = argument("reveal ") { return .reveal(value) }
        if let value = argument("press ") { return .shortcut(value.lowercased()) }
        if let value = argument("click ") {
            if let number = Self.number(value.lowercased()) {
                guard (1...150).contains(number) else { throw CommandError.invalid("Target numbers range from 1 to 150.") }
                return .clickNumber(number)
            }
            return .click(value)
        }
        for prefix in ["set volume to ", "volume "] {
            if let value = argument(prefix) {
                let cleaned = value.lowercased().replacingOccurrences(of: "%", with: "").replacingOccurrences(of: " percent", with: "")
                guard let number = Self.number(cleaned), (0...100).contains(number) else { throw CommandError.invalid("Volume must be between 0 and 100.") }
                return .volume(number)
            }
        }
        if let value = argument("scroll ") {
            let parts = value.lowercased().split(separator: " ").map(String.init)
            guard let direction = parts.first, ["up", "down", "left", "right"].contains(direction), parts.count <= 2 else {
                throw CommandError.invalid("Try “scroll down” or “scroll up 5”.")
            }
            let amount = parts.count == 2 ? Self.number(parts[1]) : 5
            guard let amount, (1...100).contains(amount) else { throw CommandError.invalid("Scroll amount must be between 1 and 100.") }
            return .scroll(direction, amount)
        }
        if let value = argument("wait ") {
            let cleaned = value.lowercased().replacingOccurrences(of: " seconds", with: "").replacingOccurrences(of: " second", with: "")
            guard let seconds = Double(cleaned) ?? Self.number(cleaned).map(Double.init), (0...30).contains(seconds), seconds.isFinite else {
                throw CommandError.invalid("Wait time must be between 0 and 30 seconds.")
            }
            return .wait(seconds)
        }
        throw CommandError.unknown(text)
    }

    public static func number(_ value: String) -> Int? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(clean) { return number }
        let words = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                     "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
                     "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
                     "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
                     "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100]
        let parts = clean.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
        if parts.count == 1 { return words[clean] }
        if parts.count == 2, let tens = words[parts[0]], let units = words[parts[1]], tens >= 20, tens < 100, tens % 10 == 0, (1...9).contains(units) { return tens + units }
        if clean == "one hundred" { return 100 }
        return nil
    }
}

public struct Workflow: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var commands: String
    public init(id: UUID = UUID(), name: String, commands: String) {
        self.id = id; self.name = name; self.commands = commands
    }
}

public struct WorkflowResolver {
    public init() {}
    public func expand(_ plan: CommandPlan, workflows: [Workflow]) throws -> CommandPlan {
        var stack: [String] = []
        var total = 0
        func resolve(_ actions: [Action]) throws -> [Action] {
            var result: [Action] = []
            for action in actions {
                if case .workflow(let name) = action {
                    let key = name.lowercased()
                    guard !stack.contains(key), stack.count < 8 else { throw CommandError.invalid("Workflow cycle or nesting limit reached: \(name).") }
                    guard let workflow = workflows.first(where: { $0.name.lowercased() == key }) else { throw CommandError.invalid("No workflow named “\(name)”. Create it in Workflows.") }
                    stack.append(key)
                    let lines = workflow.commands.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    guard !lines.isEmpty else { throw CommandError.invalid("Workflow “\(name)” is empty.") }
                    for line in lines { result += try resolve(CommandParser().parse(line).actions) }
                    stack.removeLast()
                } else {
                    total += 1
                    guard total <= 50 else { throw CommandError.invalid("A workflow can execute at most 50 steps.") }
                    result.append(action)
                }
            }
            return result
        }
        return CommandPlan(transcript: plan.transcript, actions: try resolve(plan.actions), requiresReview: plan.requiresReview)
    }
}

public struct ModelPlan: Decodable {
    public let commands: [String]
    public let explanation: String
    public func validated(transcript: String, workflows: [Workflow]) throws -> CommandPlan {
        guard !commands.isEmpty, commands.count <= 20, commands.allSatisfy({ $0.count <= 4000 }) else { throw CommandError.invalid("The model did not return a supported plan. Try a more specific command.") }
        var actions: [Action] = []
        for command in commands { actions += try CommandParser().parse(command).actions }
        let expanded = try WorkflowResolver().expand(CommandPlan(transcript: transcript, actions: actions, requiresReview: true), workflows: workflows)
        guard !expanded.actions.contains(where: { if case .shell = $0 { return true }; return false }) else { throw CommandError.invalid("AI plans cannot execute shell commands, including inside workflows. Use an explicit shell command instead.") }
        return expanded
    }
}

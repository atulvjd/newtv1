import Foundation

public struct ScheduledRoutine: Codable, Equatable, Identifiable {
    public enum Repetition: String, Codable, CaseIterable { case once, daily, weekdays, weekly }
    public var id: UUID
    public var name: String
    public var commands: String
    public var nextRun: Date
    public var repetition: Repetition
    public var enabled: Bool
    public var awaitingReview: Bool
    public var lastTriggered: Date?
    public var weekdays: [Int]? = nil
    public var executionPolicy: RoutineExecutionPolicy? = nil
    public var approvedActions: [Action]? = nil
    public init(id: UUID = UUID(), name: String, commands: String, nextRun: Date, repetition: Repetition = .once, weekdays: [Int]? = nil) {
        self.id = id; self.name = name; self.commands = commands; self.nextRun = nextRun
        self.repetition = repetition; enabled = true; awaitingReview = false
        self.weekdays = weekdays.map { Array(Set($0.filter { (1...7).contains($0) })).sorted() }
    }
    /// Coalesce missed occurrences into one review instead of replaying a backlog.
    public mutating func trigger(at now: Date, calendar: Calendar = .current) {
        guard enabled, !awaitingReview, nextRun <= now else { return }
        awaitingReview = true; lastTriggered = now
        if repetition == .once { enabled = false; return }
        let components = calendar.dateComponents([.hour, .minute, .second, .weekday], from: nextRun)
        var match = DateComponents(hour: components.hour, minute: components.minute, second: components.second)
        if repetition == .weekly {
            let days = weekdays?.filter { (1...7).contains($0) } ?? []
            if !days.isEmpty {
                let candidates = Set(days).compactMap { day -> Date? in
                    var selected = match; selected.weekday = day
                    return calendar.nextDate(after: now, matching: selected, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
                }
                guard let next = candidates.min() else { enabled = false; return }
                nextRun = next; return
            }
            match.weekday = components.weekday
        }
        guard var next = calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime, repeatedTimePolicy: .first) else { enabled = false; return }
        if repetition == .weekdays {
            for _ in 0..<7 where calendar.isDateInWeekend(next) {
                guard let following = calendar.nextDate(after: next, matching: match, matchingPolicy: .nextTime) else { enabled = false; return }
                next = following
            }
        }
        nextRun = next
    }
    public func plan(workflows: [Workflow]) throws -> CommandPlan {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              !commands.isEmpty, commands.count <= 16000 else { throw CommandError.invalid("A routine needs a name and up to 16,000 characters of commands.") }
        let snapshot = Workflow(name: "scheduled-" + id.uuidString, commands: commands)
        let plan = try WorkflowResolver().expand(CommandPlan(transcript: name, actions: [.workflow(snapshot.name)]), workflows: workflows + [snapshot])
        return CommandPlan(transcript: "Scheduled: " + name, actions: plan.actions, requiresReview: true)
    }
    public func automaticPlan(workflows: [Workflow]) throws -> CommandPlan? {
        guard executionPolicy == .approvedLocal else { return nil }
        let proposed = try plan(workflows: workflows)
        guard proposed.actions == approvedActions, RoutineExecutionPolicy.supportsAutomatic(proposed.actions) else { return nil }
        return CommandPlan(transcript: proposed.transcript, actions: proposed.actions)
    }
}

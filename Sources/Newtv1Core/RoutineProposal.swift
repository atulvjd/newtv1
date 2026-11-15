import Foundation

public struct RoutineProposal: Codable {
    public let operation: String
    public let explanation: String
    public let routineID: String
    public let name: String
    public let commands: [String]
    public let firstRun: String
    public let repetition: String
    public let weekdays: [Int]
    public func validated(routines: [ScheduledRoutine], workflows: [Workflow], now: Date = Date()) throws -> ScheduledRoutine? {
        guard ["create", "update", "pause", "resume", "delete", "question"].contains(operation), explanation.count <= 4000 else { throw CommandError.invalid("Invalid routine response.") }
        if operation == "question" { return nil }
        let existing = routines.first { $0.id.uuidString.lowercased() == routineID.lowercased() }
        guard operation == "create" ? routineID.isEmpty : existing != nil else { throw CommandError.invalid("That schedule no longer exists. Ask again using its name.") }
        if ["pause", "resume", "delete"].contains(operation) { return existing }
        guard let repetition = ScheduledRoutine.Repetition(rawValue: repetition), !commands.isEmpty, commands.count <= 20,
              weekdays.count <= 7, Set(weekdays).count == weekdays.count, weekdays.allSatisfy({ (1...7).contains($0) }),
              let date = ISO8601DateFormatter().date(from: firstRun), date > now,
              date.timeIntervalSince(now) < 366 * 86400 * 5 else { throw CommandError.invalid("The proposed schedule has an invalid time or recurrence. Ask for a future date with a time zone.") }
        var item = ScheduledRoutine(id: existing?.id ?? UUID(), name: name, commands: commands.joined(separator: "\n"), nextRun: date, repetition: repetition, weekdays: repetition == .weekly ? weekdays : nil)
        if repetition == .weekly, !weekdays.isEmpty, !weekdays.contains(Calendar.current.component(.weekday, from: date)) {
            // Calendar arithmetic determines dates; model-supplied weekday/date pairs can disagree.
            // Preserve its proposed start date and local clock, then advance to a selected weekday.
            let calendar = Calendar.current
            let clock = calendar.dateComponents([.hour, .minute, .second], from: date)
            let candidates = weekdays.compactMap { day -> Date? in
                var match = clock; match.weekday = day
                return calendar.nextDate(after: date.addingTimeInterval(-1), matching: match, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
            }
            guard let next = candidates.min() else { throw CommandError.invalid("Could not calculate the next selected weekday.") }
            item.nextRun = next
        }
        let plan = try item.plan(workflows: workflows)
        guard !plan.actions.contains(where: { if case .shell = $0 { return true }; return false }) else { throw CommandError.invalid("AI routines cannot contain shell commands, including nested workflows.") }
        return item
    }
}

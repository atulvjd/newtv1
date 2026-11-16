import Foundation
import Newtv1Core

// Read-only hardware checks plus a short-lived IOKit assertion, released before exit.
// No audio is opened, no credentials read, and no settings/network/media are changed.
struct Newtv1Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
final class ProcessRunner {
    func run(_ path: String, _ arguments: [String], timeout: Double = 30) async throws -> String {
        fatalError("Native checks must not launch a process or change system settings")
    }
}
@main
struct SystemControlChecks {
    @MainActor static func main() async throws {
        var totalDevices = 0
        for direction in [AudioDirection.input, .output] {
            let devices = SystemAudio.devices(direction)
            totalDevices += devices.count
            precondition(Set(devices.map(\.id)).count == devices.count, "Audio UIDs must be unique")
            let selected = SystemAudio.selected(direction)
            if selected != 0 { precondition(devices.contains { $0.objectID == selected }, "Default audio device wasn't enumerated") }
            if let level = SystemAudio.level(selected, direction) { precondition(level.isFinite && (0...1).contains(level)) }
            print("PASS \(direction.rawValue) device enumeration, selected identity and readable level (\(devices.count) devices)")
        }
        precondition(totalDevices > 0, "No Core Audio hardware is visible. Run outside a restricted sandbox.")
        let controls = SystemControls()
        controls.refresh()
        defer { controls.endKeepAwake() }
        let action = SystemCommand.keepAwake(1)
        _ = try await controls.perform(action, runner: ProcessRunner())
        guard let end = controls.awakeUntil else { fatalError("Missing keep-awake session") }
        precondition((55...61).contains(end.timeIntervalSinceNow))
        let verification = try controls.verification(action)
        precondition(verification.contains("created"))
        _ = try await controls.perform(.allowSleep, runner: ProcessRunner())
        precondition(controls.awakeUntil == nil)
        controls.endKeepAwake() // idempotent cleanup
        print("PASS native timed IOKit assertion creation, command verification and release")
    }
}

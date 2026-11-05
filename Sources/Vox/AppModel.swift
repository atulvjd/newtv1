import SwiftUI
import AppKit
import ApplicationServices
import Speech
import AVFoundation
import Carbon
import VoxCore

struct Activity: Identifiable {
    let id = UUID()
    let date = Date()
    let command: String
    var detail: String
    var state: State
    enum State { case running, success, failed, cancelled }
}

enum AppPage: String, CaseIterable {
    case control = "Command center", workflows = "Workflows", guide = "Command guide", settings = "Settings"
    var icon: String {
        switch self { case .control: return "waveform"; case .workflows: return "square.stack.3d.up"; case .guide: return "command"; case .settings: return "slider.horizontal.3" }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var page: AppPage = .control
    @Published var input = ""
    @Published var activities: [Activity] = []
    @Published var busy = false
    @Published var pending: CommandPlan?
    @Published var error: String?
    @Published var targetName = "Choose an app"
    @Published var accessibility = AXIsProcessTrusted()
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var speechPermission = SFSpeechRecognizer.authorizationStatus() == .authorized
    @Published var speechStarting = false
    @Published var useLocalPlanner: Bool { didSet { UserDefaults.standard.set(useLocalPlanner, forKey: "useLocalPlanner") } }
    @Published var localModel: String { didSet { UserDefaults.standard.set(localModel, forKey: "localModel") } }
    @Published var wakeWord: Bool { didSet { UserDefaults.standard.set(wakeWord, forKey: "wakeWord") } }
    @Published var allowNetwork: Bool { didSet { UserDefaults.standard.set(allowNetwork, forKey: "allowNetwork"); speech.stop() } }
    @Published var workflows: [Workflow] { didSet { saveWorkflows() } }
    let speech = SpeechController()
    let automation = Automation()
    private var execution: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var hotkey = GlobalHotkey()

    init() {
        wakeWord = UserDefaults.standard.object(forKey: "wakeWord") as? Bool ?? true
        allowNetwork = UserDefaults.standard.bool(forKey: "allowNetwork")
        useLocalPlanner = UserDefaults.standard.bool(forKey: "useLocalPlanner")
        localModel = UserDefaults.standard.string(forKey: "localModel") ?? ""
        if let data = UserDefaults.standard.data(forKey: "workflows"), let saved = try? JSONDecoder().decode([Workflow].self, from: data) { workflows = saved }
        else { workflows = [Workflow(name: "focus mode", commands: "open Safari\nleft half\nopen Notes\nright half\nvolume 25")] }
        updateTarget(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.automation.externalAppActivated(app) }
                self.updateTarget(app)
            }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermissions() }
        }
        speech.onUtterance = { [weak self] text in self?.receiveVoice(text) }
        speech.onFailure = { [weak self] message in self?.error = message }
        hotkey.onToggle = { [weak self] in Task { @MainActor in self?.toggleListening() } }
        hotkey.register()
    }

    private func updateTarget(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else { return }
        automation.targetApp = app; targetName = app.localizedName ?? "App"
    }

    func refreshPermissions() {
        accessibility = AXIsProcessTrusted()
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechPermission = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func toggleListening() {
        guard !speechStarting else { return }
        if speech.isListening { speech.stop() }
        else {
            speechStarting = true
            Task { await speech.start(allowNetwork: allowNetwork); speechStarting = false; refreshPermissions() }
        }
    }

    func receiveVoice(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if wakeWord {
            // Only an explicit prefix arms a command; background mentions never execute.
            let prefixes = ["hey vox ", "hey vox, ", "vox ", "vox, "]
            guard let prefix = prefixes.first(where: { text.lowercased().hasPrefix($0) }) else { return }
            text = String(text.dropFirst(prefix.count))
        }
        let lower = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if ["stop", "stop listening", "cancel everything"].contains(lower) { stop(); speech.stop(); return }
        if lower == "cancel" { pending = nil; return }
        if lower == "confirm" {
            // Shell code needs a deliberate on-screen review, not ambient speech approval.
            if let pending, !pending.requiresReview, !pending.actions.contains(where: { if case .shell = $0 { return true }; return false }) { approve() }
            return
        }
        guard !busy, pending == nil else { return }
        submit(text)
    }

    func submit(_ command: String? = nil) {
        guard !busy, pending == nil else { return }
        let text = command ?? input
        do {
            let plan = try WorkflowResolver().expand(CommandParser().parse(text), workflows: workflows)
            input = ""; error = nil
            if plan.needsConfirmation { pending = plan; NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }
            else { run(plan) }
        } catch CommandError.unknown where useLocalPlanner {
            planWithLocalModel(text)
        } catch { self.error = error.localizedDescription }
    }

    private func planWithLocalModel(_ text: String) {
        busy = true; error = nil
        let activity = Activity(command: text, detail: "Planning with local model…", state: .running)
        activities.insert(activity, at: 0)
        execution = Task {
            do {
                let plan = try await LocalPlanner().plan(text, model: localModel, target: targetName, workflows: workflows)
                try Task.checkCancellation()
                pending = plan; input = ""
                update(activity.id, detail: "Plan ready for review. No actions executed.", state: .success)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                update(activity.id, detail: cancelled ? "Planning cancelled." : error.localizedDescription, state: cancelled ? .cancelled : .failed)
                if !cancelled { self.error = error.localizedDescription }
            }
            busy = false; execution = nil
        }
    }

    func approve() {
        guard let plan = pending else { return }
        pending = nil; run(plan)
    }

    private func run(_ plan: CommandPlan) {
        busy = true
        let activity = Activity(command: plan.transcript, detail: "Preparing \(plan.actions.count) step\(plan.actions.count == 1 ? "" : "s")…", state: .running)
        activities.insert(activity, at: 0)
        activities = Array(activities.prefix(60))
        execution = Task {
            var results: [String] = []
            do {
                for (index, action) in plan.actions.enumerated() {
                    try Task.checkCancellation()
                    update(activity.id, detail: "\(index + 1)/\(plan.actions.count) · \(action.summary)", state: .running)
                    let result = try await automation.execute(action)
                    results.append(result)
                    targetName = automation.targetApp?.localizedName ?? targetName
                    try Task.checkCancellation()
                    if index < plan.actions.count - 1 { try await Task.sleep(nanoseconds: 150_000_000) }
                }
                update(activity.id, detail: results.joined(separator: "\n"), state: .success)
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                update(activity.id, detail: cancelled ? "Stopped. Completed actions have not been undone." : error.localizedDescription, state: cancelled ? .cancelled : .failed)
                if !cancelled { self.error = error.localizedDescription }
            }
            busy = false; execution = nil
        }
    }

    private func update(_ id: UUID, detail: String, state: Activity.State) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].detail = detail; activities[index].state = state
    }

    func stop() {
        execution?.cancel(); automation.runner.stop(); automation.hideNumbers(); pending = nil
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
    }

    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") { NSWorkspace.shared.open(url) }
    }

    func saveWorkflow(name: String, commands: String, replacing id: UUID? = nil) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !commands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoxFailure("Give the workflow a name and at least one command.") }
        guard !workflows.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { throw VoxFailure("That workflow name is already taken.") }
        let workflow = Workflow(id: id ?? UUID(), name: name, commands: commands)
        var proposed = workflows.filter { $0.id != id }; proposed.append(workflow)
        _ = try WorkflowResolver().expand(CommandPlan(transcript: name, actions: [.workflow(name)]), workflows: proposed)
        workflows = proposed
    }

    private func saveWorkflows() {
        if let data = try? JSONEncoder().encode(workflows) { UserDefaults.standard.set(data, forKey: "workflows") }
    }
}

final class GlobalHotkey {
    var onToggle: (() -> Void)?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue().onToggle?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: 0x564F5858, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotkey)
    }
    deinit { if let hotkey { UnregisterEventHotKey(hotkey) }; if let handler { RemoveEventHandler(handler) } }
}

import SwiftUI
import AppKit
import ApplicationServices
import Speech
import AVFoundation
import Carbon
import Newtv1Core

struct Activity: Identifiable {
    let id = UUID()
    let date = Date()
    let command: String
    var detail: String
    var state: State
    enum State { case running, success, failed, cancelled }
}

struct BrainAnswer: Identifiable {
    let id = UUID()
    let question: String
    let markdown: String
}

enum AppPage: String, CaseIterable {
    case control = "Command center", brain = "Brain", workflows = "Workflows", guide = "Command guide", settings = "Settings"
    var icon: String {
        switch self { case .control: return "waveform"; case .brain: return "sparkles"; case .workflows: return "square.stack.3d.up"; case .guide: return "command"; case .settings: return "slider.horizontal.3" }
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
    @Published var brainAnswers: [BrainAnswer] = []
    @Published var keyConfigured: Bool
    @Published var useOpenAI: Bool { didSet { UserDefaults.standard.set(useOpenAI, forKey: "useOpenAI") } }
    @Published var allowWebSearch: Bool { didSet { UserDefaults.standard.set(allowWebSearch, forKey: "allowWebSearch") } }
    @Published var openAIModel: String { didSet { UserDefaults.standard.set(openAIModel, forKey: "openAIModel") } }
    @Published var useLocalPlanner: Bool { didSet { UserDefaults.standard.set(useLocalPlanner, forKey: "useLocalPlanner") } }
    @Published var localModel: String { didSet { UserDefaults.standard.set(localModel, forKey: "localModel") } }
    @Published var wakeWord: Bool { didSet { UserDefaults.standard.set(wakeWord, forKey: "wakeWord") } }
    @Published var allowNetwork: Bool { didSet { UserDefaults.standard.set(allowNetwork, forKey: "allowNetwork"); speech.stop() } }
    @Published var workflows: [Workflow] { didSet { saveWorkflows() } }
    let speech = SpeechController()
    let automation = Automation()
    var onOpenCommandCenter: (() -> Void)?
    private var execution: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var hotkey = GlobalHotkey()

    init() {
        // Keep existing routines when upgrading from the original development name.
        let defaults = UserDefaults.standard
        keyConfigured = defaults.bool(forKey: "openAIKeyConfigured")
        useOpenAI = defaults.bool(forKey: "useOpenAI")
        allowWebSearch = defaults.object(forKey: "allowWebSearch") as? Bool ?? true
        openAIModel = defaults.string(forKey: "openAIModel") ?? "gpt-5.4-mini"
        if !defaults.bool(forKey: "migratedPreviousIdentity") {
            let previous = defaults.persistentDomain(forName: "dev.vox.mac") ?? [:]
            for key in ["workflows", "wakeWord", "allowNetwork", "useLocalPlanner", "localModel"] where defaults.object(forKey: key) == nil {
                if let value = previous[key] { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "migratedPreviousIdentity")
        }
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
        guard let text = VoiceCommand.extract(raw, requireWakePhrase: wakeWord) else { return }
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
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let searchPrefixes = ["research ", "look up ", "search for ", "search "]
        if useOpenAI, let prefix = searchPrefixes.first(where: { lower.hasPrefix($0) }) {
            requestBrain(String(text.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(prefix.count)), mode: .search); return
        }
        if lower.hasPrefix("ask ") {
            guard useOpenAI else { error = "Enable the OpenAI brain in Settings to ask questions."; return }
            requestBrain(String(text.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst(4)), mode: .answer); return
        }
        do {
            let plan = try WorkflowResolver().expand(CommandParser().parse(text), workflows: workflows)
            input = ""; error = nil
            if plan.needsConfirmation { pending = plan; openCommandCenter() }
            else { run(plan) }
        } catch CommandError.unknown where useOpenAI {
            requestBrain(text, mode: .decide)
        } catch CommandError.unknown where useLocalPlanner {
            planWithLocalModel(text)
        } catch { self.error = error.localizedDescription }
    }

    enum BrainMode { case answer, search, decide }

    func requestBrain(_ text: String, mode: BrainMode) {
        guard !busy, pending == nil else { return }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { error = "Ask a question first."; return }
        guard useOpenAI, keyConfigured else { error = "Save your OpenAI API key in Settings first."; return }
        let name = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Choose an OpenAI model in Settings."; return }
        busy = true; error = nil; input = ""
        let activity = Activity(command: question, detail: mode == .search ? "Searching the web…" : "Thinking with OpenAI…", state: .running)
        activities.insert(activity, at: 0); activities = Array(activities.prefix(60))
        execution = Task {
            do {
                guard let key = try KeychainStore.load() else { throw Newtv1Failure("No API key in Keychain. Save it in Settings.") }
                let brain = OpenAIBrain()
                var answer: String?
                if mode == .decide {
                    let decision = try await brain.decide(question, model: name, key: key, target: targetName, workflows: workflows)
                    try Task.checkCancellation()
                    switch decision.intent {
                    case "actions":
                        pending = try decision.actionPlan(transcript: question, workflows: workflows)
                        update(activity.id, detail: "AI plan ready for review. No actions executed.", state: .success)
                        openCommandCenter(page: .control)
                    case "search":
                        guard !decision.search_query.isEmpty else { throw Newtv1Failure("Please make the search more specific.") }
                        answer = try await brain.answer(decision.search_query, model: name, key: key, search: true, allowWeb: allowWebSearch)
                    case "answer": answer = decision.answer
                    default: throw Newtv1Failure("The brain returned an unsupported response.")
                    }
                } else { answer = try await brain.answer(question, model: name, key: key, search: mode == .search, allowWeb: allowWebSearch) }
                try Task.checkCancellation()
                if let answer, !answer.isEmpty {
                    brainAnswers.insert(BrainAnswer(question: question, markdown: answer), at: 0)
                    brainAnswers = Array(brainAnswers.prefix(30))
                    update(activity.id, detail: "Answered in Brain. No Mac actions executed.", state: .success)
                    openCommandCenter(page: .brain)
                }
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                update(activity.id, detail: cancelled ? "Cancelled." : error.localizedDescription, state: cancelled ? .cancelled : .failed)
                if !cancelled { self.error = error.localizedDescription }
            }
            busy = false; execution = nil
        }
    }

    func saveOpenAIKey(_ value: String) throws {
        try KeychainStore.save(value)
        keyConfigured = true
        UserDefaults.standard.set(true, forKey: "openAIKeyConfigured")
        useOpenAI = true
    }

    func removeOpenAIKey() throws {
        try KeychainStore.remove()
        keyConfigured = false; useOpenAI = false
        UserDefaults.standard.set(false, forKey: "openAIKeyConfigured")
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
                openCommandCenter()
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

    func openCommandCenter(page: AppPage? = nil) {
        if let page { self.page = page }
        onOpenCommandCenter?()
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
        guard !name.isEmpty, !commands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Newtv1Failure("Give the workflow a name and at least one command.") }
        guard !workflows.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { throw Newtv1Failure("That workflow name is already taken.") }
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

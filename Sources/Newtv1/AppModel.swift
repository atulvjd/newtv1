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

struct BrainAnswer: Identifiable, Codable {
    var id = UUID()
    let question: String
    let markdown: String
}

struct AgentJob: Identifiable, Codable {
    enum Status: String, Codable { case planning = "Planning", review = "Needs review", running = "Running", complete = "Complete", failed = "Failed", cancelled = "Cancelled", blocked = "Needs permission", paused = "Needs input" }
    let id: UUID
    let goal: String
    let createdAt: Date
    init(goal: String) { self.id = UUID(); self.goal = goal; self.createdAt = Date() }
    var trace: [String] = []
    var remaining: [Action] = []
    var status: Status = .planning
    var steps: [String] = []
    var detail = "Preparing a plan…"
    var title: String { String(goal.split(separator: " ").prefix(6).joined(separator: " ")) }
}

enum AppPage: String, CaseIterable {
    case companion = "Companion", browser = "Browser", connections = "Connections", diagrams = "Diagrams", utilities = "Utilities", routines = "Routines", control = "Command center", brain = "Brain", jobs = "Tasks", notch = "Notch Studio", workflows = "Workflows", guide = "Command guide", settings = "Settings"
    var icon: String {
        switch self { case .diagrams: return "cube.transparent"; case .browser: return "globe"; case .connections: return "point.3.connected.trianglepath.dotted"; case .utilities: return "square.grid.2x2"; case .routines: return "calendar.badge.clock"; case .companion: return "bubble.left.and.bubble.right"; case .control: return "waveform"; case .brain: return "sparkles"; case .jobs: return "checklist"; case .notch: return "rectangle.topthird.inset.filled"; case .workflows: return "square.stack.3d.up"; case .guide: return "command"; case .settings: return "slider.horizontal.3" }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var page: AppPage = .companion
    @Published var input = ""
    @Published var diagram: Diagram = .example
    @Published var activities: [Activity] = []
    @Published var busy = false
    @Published var pending: CommandPlan?
    @Published var error: String?
    @Published var targetName = "Choose an app"
    @Published var accessibility = AXIsProcessTrusted()
    @Published var blockedForAccessibility: CommandPlan?
    @Published var accessibilityIssue = false
    var controlPermissionName: String { ControlPermission.paneName(macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) }
    var runningAppPath: String { Bundle.main.bundleURL.path }
    var runningVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    @Published var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var speechPermission = SFSpeechRecognizer.authorizationStatus() == .authorized
    @Published var speechStarting = false
    @Published var brainAnswers: [BrainAnswer] = []
    @Published var assistantMode: AssistantMode { didSet { UserDefaults.standard.set(assistantMode.rawValue, forKey: "assistantMode"); speech.stop(); speaker.stop() } }
    @Published var automaticLanguage: Bool { didSet { UserDefaults.standard.set(automaticLanguage, forKey: "automaticLanguage"); speech.stop() } }
    @Published var speechLocale: String { didSet { UserDefaults.standard.set(speechLocale, forKey: "speechLocale"); speech.stop() } }
    @Published var vocabulary: String { didSet { UserDefaults.standard.set(vocabulary, forKey: "vocabulary"); speech.stop() } }
    @Published var speakAnswers: Bool { didSet { UserDefaults.standard.set(speakAnswers, forKey: "speakAnswers") } }
    @Published var voiceID: String { didSet { UserDefaults.standard.set(voiceID, forKey: "voiceID") } }
    @Published var voiceRate: Double { didSet { UserDefaults.standard.set(voiceRate, forKey: "voiceRate") } }
    @Published var pushToTalk: Bool { didSet { UserDefaults.standard.set(pushToTalk, forKey: "pushToTalk") } }
    @Published var rememberConversations: Bool { didSet { UserDefaults.standard.set(rememberConversations, forKey: "rememberConversations"); if rememberConversations { saveConversationHistory() } } }
    @Published var capturedScreen: CapturedScreen?
    @Published var approvedScreenID: UUID?
    @Published var capturingScreen = false
    @Published var screenDisplayChoice = "pointer"
    @Published var guideQuestion = ""
    @Published var localScreenText = ""
    @Published var lastGuidance: GuidanceResult?
    @Published var agentJobs: [AgentJob] = [] { didSet { saveTaskHistory() } }
    @Published var hotkeyAvailable = true
    @Published var guidedObservationPreview = ""
    @Published private(set) var guidedJobID: UUID?
    private var guidedGoal = ""
    private var guidedRequests = 0
    let speaker = AnswerSpeaker()
    let nowPlaying = NowPlaying()
    let calendar = CalendarStore()
    let files = FileStore()
    let monitor = SystemMonitor()
    let audio = AudioControls()
    let camera = CameraPreview()
    let clipboard = ClipboardStore()
    let notices = NoticeStore()
    let routines = RoutineStore()
    let browser = BrowserContext()
    let connections = Connections()
    private var utilityTicks = 0
    private let guidanceOverlay = GuidanceOverlay()
    private var guideDisplayID: UInt32?
    private var guideFrame = CGRect.zero
    private var hotkeyHeld = false
    private var pendingJobID: UUID?
    private var currentJobID: UUID?
    private var resumeListeningAfterSpeech = false
    private var armedByHotkey = false
    @Published var notch: NotchConfiguration {
        didSet { if let data = try? JSONEncoder().encode(notch.normalized()) { UserDefaults.standard.set(data, forKey: "notchConfiguration") } }
    }
    @Published var scratchpad: String { didSet { UserDefaults.standard.set(scratchpad, forKey: "notchScratchpad") } }
    @Published var notchTimerEnd: Date?
    @Published var notchTimerFinished = false
    @Published var keyConfigured: Bool
    @Published var useOpenAI: Bool { didSet { UserDefaults.standard.set(useOpenAI, forKey: "useOpenAI") } }
    @Published var allowWebSearch: Bool { didSet { UserDefaults.standard.set(allowWebSearch, forKey: "allowWebSearch") } }
    @Published var openAIModel: String { didSet { UserDefaults.standard.set(openAIModel, forKey: "openAIModel") } }
    @Published var useLocalPlanner: Bool { didSet { UserDefaults.standard.set(useLocalPlanner, forKey: "useLocalPlanner") } }
    @Published var localModel: String { didSet { UserDefaults.standard.set(localModel, forKey: "localModel") } }
    @Published var wakeWord: Bool { didSet { UserDefaults.standard.set(wakeWord, forKey: "wakeWord") } }
    @Published var customWakePhrase: String {
        didSet { UserDefaults.standard.set(customWakePhrase, forKey: "customWakePhrase"); speech.stop() }
    }
    var wakePhraseLabel: String { VoiceCommand.phrases(custom: customWakePhrase).first ?? "Newt" }
    @Published var allowNetwork: Bool { didSet { UserDefaults.standard.set(allowNetwork, forKey: "allowNetwork"); speech.stop() } }
    @Published var workflows: [Workflow] { didSet { saveWorkflows() } }
    let speech = SpeechController()
    let automation = Automation()
    var onOpenCommandCenter: (() -> Void)?
    var onPreviewNotch: (() -> Void)?
    private var execution: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var hotkey = GlobalHotkey()

    init() {
        // Keep existing routines when upgrading from the original development name.
        let defaults = UserDefaults.standard
        assistantMode = AssistantMode(rawValue: defaults.string(forKey: "assistantMode") ?? "") ?? .command
        automaticLanguage = defaults.bool(forKey: "automaticLanguage")
        speechLocale = defaults.string(forKey: "speechLocale") ?? "en-US"
        vocabulary = defaults.string(forKey: "vocabulary") ?? ""
        speakAnswers = defaults.bool(forKey: "speakAnswers")
        voiceID = defaults.string(forKey: "voiceID") ?? ""
        voiceRate = defaults.object(forKey: "voiceRate") as? Double ?? 0.48
        pushToTalk = defaults.bool(forKey: "pushToTalk")
        rememberConversations = defaults.bool(forKey: "rememberConversations")
        notch = defaults.data(forKey: "notchConfiguration").flatMap { try? NotchConfiguration.profile($0) } ?? NotchConfiguration()
        scratchpad = defaults.string(forKey: "notchScratchpad") ?? ""
        customWakePhrase = defaults.string(forKey: "customWakePhrase") ?? ""
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshPermissions(); self.monitor.refresh(); self.clipboard.poll(); self.audio.refresh()
                self.utilityTicks += 1
                if self.utilityTicks % 5 == 0 { self.files.refresh(); self.calendar.refresh() }
                for name in self.routines.tick() { self.notices.add("Routine ready: " + name, detail: "Review its steps in Routines before running."); self.onPreviewNotch?() }
            }
        }
        speech.onUtterance = { [weak self] text in self?.receiveVoice(text) }
        speech.onFailure = { [weak self] message in self?.error = message }
        hotkey.onToggle = { [weak self] in Task { @MainActor in self?.hotkeyDown() } }
        hotkey.onRelease = { [weak self] in Task { @MainActor in self?.hotkeyUp() } }
        hotkeyAvailable = hotkey.register()
        speaker.onFinished = { [weak self] in
            guard let self, self.resumeListeningAfterSpeech else { return }
            self.resumeListeningAfterSpeech = false
            self.startListening(hold: false)
        }
        loadConversationHistory()
        loadTaskHistory()
    }

    private func updateTarget(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else { return }
        if automation.targetApp?.processIdentifier != app.processIdentifier { guidanceOverlay.hide() }
        automation.targetApp = app; targetName = app.localizedName ?? "App"
    }

    func refreshPermissions() {
        accessibility = AXIsProcessTrusted()
        if accessibility, accessibilityIssue {
            accessibilityIssue = false
            error = nil
        }
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechPermission = SFSpeechRecognizer.authorizationStatus() == .authorized
        if let end = notchTimerEnd, end <= Date() { notchTimerEnd = nil; notchTimerFinished = true; notices.add("Timer finished", detail: "Your notch timer has ended."); onPreviewNotch?() }
    }

    func startNotchTimer(minutes: Int) {
        notchTimerFinished = false
        notchTimerEnd = Date().addingTimeInterval(Double(max(1, min(minutes, 180))) * 60)
    }

    func reviewRoutine(_ routine: ScheduledRoutine) {
        guard !busy, !capturingScreen, pending == nil else { error = "Finish the current request before reviewing a routine."; return }
        do {
            pending = try routine.plan(workflows: workflows)
            pendingJobID = beginAgentJob("Scheduled: " + routine.name)
            updateJob(pendingJobID, status: .review, detail: "Scheduled routine ready for review.", steps: pending?.actions.map(\.summary))
            routines.dismiss(routine.id)
            openCommandCenter(page: .control)
        } catch { self.error = error.localizedDescription }
    }

    func cancelNotchTimer() { notchTimerEnd = nil; notchTimerFinished = false }

    func toggleListening() {
        guard !speechStarting, !capturingScreen else { return }
        if speech.isListening { speech.stop() }
        else { startListening(hold: false) }
    }

    private func startListening(hold: Bool) {
            guard !speechStarting else { return }
            if assistantMode == .dictate, !AXIsProcessTrusted() {
                accessibilityIssue = true; error = "Dictation needs Mac control access to type into another app."; openCommandCenter(page: .settings); return
            }
            if automaticLanguage, !useOpenAI || !keyConfigured { error = "Automatic language recognition sends audio to OpenAI. Connect the API key in Settings first."; return }
            speaker.stop()
            speech.automaticLanguage = automaticLanguage
            speech.transcribeAudio = { audio in
                guard let key = try KeychainStore.load() else { throw Newtv1Failure("Save your API key in Settings first.") }
                return try await OpenAIBrain().transcribe(wav: audio, key: key)
            }
            armedByHotkey = hold
            speechStarting = true
            speech.wakePhrases = VoiceCommand.recognitionPhrases(custom: customWakePhrase)
            speech.localeIdentifier = speechLocale
            speech.vocabulary = vocabulary.components(separatedBy: .newlines).map { String($0.prefix(80)) }.filter { !$0.isEmpty }
            speech.dictation = assistantMode == .dictate
            speech.submitsOnPause = !hold
            Task { await speech.start(allowNetwork: allowNetwork); speechStarting = false; refreshPermissions(); if hold, !hotkeyHeld { speech.finishUtterance() } }
    }
    private func hotkeyDown() {
        hotkeyHeld = true
        if pushToTalk { if !speechStarting { speech.stop(); startListening(hold: true) } }
        else { toggleListening() }
    }
    private func hotkeyUp() {
        hotkeyHeld = false
        if pushToTalk { speech.finishUtterance() }
    }

    func receiveVoice(_ raw: String) {
        if assistantMode == .dictate {
            if DictationControl.shouldStop(raw, custom: customWakePhrase) { speech.stop(); return }
            guard !busy, pending == nil else { return }
            run(CommandPlan(transcript: "Dictation", actions: [.typeText(raw + " ")]))
            return
        }
        let explicitlyArmed = armedByHotkey
        armedByHotkey = false
        guard let text = VoiceCommand.extract(raw, requireWakePhrase: wakeWord && !explicitlyArmed, custom: customWakePhrase) else { return }
        let lower = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if ["stop", "stop listening", "cancel everything"].contains(lower) { stop(); speech.stop(); return }
        if lower == "cancel" { cancelPendingPlan(); return }
        if lower == "start dictation" || lower == "dictate mode" { assistantMode = .dictate; startListening(hold: false); return }
        if lower == "hide guide" { hideGuidance(); return }
        if lower == "show guide" { showLastGuidance(); return }
        if lower.hasPrefix("guide ") { guideQuestion = String(text.dropFirst(6)); captureScreenForReview(); return }
        if lower == "confirm" {
            // Shell code needs a deliberate on-screen review, not ambient speech approval.
            if let pending, !pending.requiresReview, !pending.actions.contains(where: { if case .shell = $0 { return true }; return false }) { approve() }
            return
        }
        guard !busy, pending == nil else { return }
        processCompanionInput(text)
    }

    func processCompanionInput(_ text: String) {
        switch assistantMode {
        case .command: submit(text)
        case .talk: requestBrain(text, mode: .answer)
        case .guide: guideQuestion = text; captureScreenForReview()
        case .dictate: error = "Start listening in Dictate mode to insert speech into your target app."
        case .agent:
            if useOpenAI { requestBrain(text, mode: .decide) }
            else if useLocalPlanner { planWithLocalModel(text) }
            else { error = "Connect OpenAI or a local Ollama model to plan a task." }
        }
    }

    func submit(_ command: String? = nil) {
        guard !busy, !capturingScreen, pending == nil else { return }
        let text = command ?? input
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.hasPrefix("guide ") { guideQuestion = String(text.dropFirst(6)); captureScreenForReview(); return }
        if lower == "hide guide" { guidanceOverlay.hide(); return }
        if lower == "show guide" { showLastGuidance(); return }
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

    func requestBrain(_ text: String, mode: BrainMode, browserPage: BrowserPage? = nil) {
        guard !busy, !capturingScreen, pending == nil else { return }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { error = "Ask a question first."; return }
        guard question.count <= 16000 else { error = "Please keep a request under 16,000 characters."; return }
        guard useOpenAI, keyConfigured else { error = "Save your OpenAI API key in Settings first."; return }
        let name = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { error = "Choose an OpenAI model in Settings."; return }
        busy = true; error = nil; input = ""
        let activity = Activity(command: question, detail: mode == .search ? "Searching the web…" : "Thinking with OpenAI…", state: .running)
        let jobID = assistantMode == .agent ? beginAgentJob(question) : nil
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
                        pendingJobID = jobID
                        updateJob(jobID, status: .review, detail: "Review the proposed steps before running.", steps: pending?.actions.map(\.summary))
                        update(activity.id, detail: "AI plan ready for review. No actions executed.", state: .success)
                        openCommandCenter(page: .control)
                    case "search":
                        guard !decision.search_query.isEmpty else { throw Newtv1Failure("Please make the search more specific.") }
                        answer = try await brain.answer(decision.search_query, model: name, key: key, search: true, allowWeb: allowWebSearch)
                    case "answer": answer = decision.answer
                    default: throw Newtv1Failure("The brain returned an unsupported response.")
                    }
                } else { answer = try await brain.answer(question, model: name, key: key, search: mode == .search, allowWeb: allowWebSearch, history: conversationContext(), browserPage: browserPage) }
                try Task.checkCancellation()
                if let answer, !answer.isEmpty {
                    brainAnswers.insert(BrainAnswer(question: question, markdown: answer), at: 0)
                    brainAnswers = Array(brainAnswers.prefix(30))
                    saveConversationHistory()
                    if speakAnswers { speakAnswer(answer) }
                    updateJob(jobID, status: .complete, detail: "Answered. No Mac actions were executed.")
                    update(activity.id, detail: "Answered in Brain. No Mac actions executed.", state: .success)
                    openCommandCenter(page: assistantMode == .talk || assistantMode == .agent ? .companion : .brain)
                }
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                update(activity.id, detail: cancelled ? "Cancelled." : error.localizedDescription, state: cancelled ? .cancelled : .failed)
                if !cancelled { self.error = error.localizedDescription }
                updateJob(jobID, status: cancelled ? .cancelled : .failed, detail: error.localizedDescription)
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
        let jobID = assistantMode == .agent ? beginAgentJob(text) : nil
        let activity = Activity(command: text, detail: "Planning with local model…", state: .running)
        activities.insert(activity, at: 0)
        execution = Task {
            do {
                let plan = try await LocalPlanner().plan(text, model: localModel, target: targetName, workflows: workflows)
                try Task.checkCancellation()
                pending = plan; input = ""
                pendingJobID = jobID
                updateJob(jobID, status: .review, detail: "Review the proposed local plan.", steps: plan.actions.map(\.summary))
                update(activity.id, detail: "Plan ready for review. No actions executed.", state: .success)
                openCommandCenter()
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                update(activity.id, detail: cancelled ? "Planning cancelled." : error.localizedDescription, state: cancelled ? .cancelled : .failed)
                if !cancelled { self.error = error.localizedDescription }
                updateJob(jobID, status: cancelled ? .cancelled : .failed, detail: error.localizedDescription)
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
        refreshPermissions()
        guard !plan.requiresAccessibility || accessibility else {
            blockedForAccessibility = plan
            updateJob(pendingJobID, status: .blocked, detail: "Grant Mac control access, then retry manually.")
            accessibilityIssue = true
            error = "Mac control access is required. Enable this Newtv1 copy in Privacy & Security → \(controlPermissionName). No steps were started."
            openCommandCenter(page: .settings)
            return
        }
        blockedForAccessibility = nil
        let jobID = pendingJobID; pendingJobID = nil; currentJobID = jobID
        if let i = agentJobs.firstIndex(where: { $0.id == jobID }) { agentJobs[i].remaining = plan.actions; agentJobs[i].trace.append("Approved run started at " + Date().formatted()) }
        updateJob(jobID, status: .running, detail: "Executing the approved plan.", steps: plan.actions.map(\.summary))
        if jobID != nil, plan.requiresAccessibility { automation.watchForUserInterruption { [weak self] in self?.stop() } }
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
                    updateJob(jobID, status: .running, detail: "Step \(index + 1)/\(plan.actions.count): \(action.summary)")
                    if let i = agentJobs.firstIndex(where: { $0.id == jobID }) { agentJobs[i].remaining = Array(plan.actions.dropFirst(index)) }
                    let before = jobID != nil ? automation.localObservation() : ""
                    let result = try await automation.execute(action)
                    var verification = "Command dispatched; semantic outcome requires inspection."
                    if jobID != nil {
                        try await Task.sleep(nanoseconds: 180_000_000)
                        verification = try automation.verify(action)
                        if let i = agentJobs.firstIndex(where: { $0.id == jobID }) {
                            agentJobs[i].trace.append("Step \(index + 1): \(action.summary)\nBefore: \(before)\nAfter: \(automation.localObservation())\n\(verification)")
                            agentJobs[i].remaining = Array(plan.actions.dropFirst(index + 1))
                        }
                    }
                    results.append(result + (jobID != nil ? " · " + verification : ""))
                    targetName = automation.targetApp?.localizedName ?? targetName
                    try Task.checkCancellation()
                    if index < plan.actions.count - 1 { try await Task.sleep(nanoseconds: 150_000_000) }
                }
                update(activity.id, detail: results.joined(separator: "\n"), state: .success)
                updateJob(jobID, status: .complete, detail: results.joined(separator: "\n"))
                if jobID != nil, guidedJobID != jobID { notices.add("Task finished", detail: plan.transcript) }
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                update(activity.id, detail: cancelled ? "Stopped. Completed actions have not been undone." : error.localizedDescription, state: cancelled ? .cancelled : .failed)
                if !cancelled { self.error = error.localizedDescription }
                updateJob(jobID, status: cancelled ? .cancelled : .failed, detail: error.localizedDescription)
            }
            automation.stopWatchingForInterruption()
            busy = false; execution = nil; currentJobID = nil
            if !Task.isCancelled, jobID != nil, jobID == guidedJobID,
               agentJobs.first(where: { $0.id == jobID })?.status == .complete { requestGuidedStep() }
        }
    }

    private func update(_ id: UUID, detail: String, state: Activity.State) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].detail = detail; activities[index].state = state
    }

    func stop() {
        camera.stop()
        guidedJobID = nil; guidedGoal = ""; guidedObservationPreview = ""
        execution?.cancel(); automation.runner.stop(); automation.hideNumbers(); pending = nil
        blockedForAccessibility = nil
        updateJob(currentJobID ?? pendingJobID, status: .cancelled, detail: "Stopped by you. Completed actions were not rolled back.")
        pendingJobID = nil; currentJobID = nil
        speaker.stop(); guidanceOverlay.hide(); capturedScreen = nil; approvedScreenID = nil
        resumeListeningAfterSpeech = false
        armedByHotkey = false
        automation.stopWatchingForInterruption()
        if accessibilityIssue { accessibilityIssue = false; error = nil }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            // The legacy Privacy_Accessibility anchor opens only the root pane on this OS.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
        } else { openPrivacy("Accessibility") }
    }

    func revealRunningApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }

    func retryAfterAccessibility() {
        refreshPermissions()
        guard accessibility else {
            error = "Newtv1 still has no Mac control access. If its switch is already on, quit Newtv1, remove its old entry, add the app shown below, enable it, then reopen Newtv1."
            accessibilityIssue = true
            return
        }
        guard let plan = blockedForAccessibility else { return }
        // Revisit approval rather than resuming a previously approved sensitive plan silently.
        blockedForAccessibility = nil
        if plan.needsConfirmation { pending = plan; openCommandCenter(page: .control) }
        else { run(plan) }
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

    func cancelPendingPlan() {
        pending = nil
        updateJob(pendingJobID, status: .cancelled, detail: "Plan declined. No actions executed.")
        pendingJobID = nil; guidedJobID = nil
    }
    func reviewSheetDismissed() {
        if pending == nil, blockedForAccessibility == nil, currentJobID == nil, pendingJobID != nil { cancelPendingPlan() }
    }

    func captureScreenForReview() {
        guard !busy, !capturingScreen, pending == nil else { return }
        speech.stop(); speaker.stop(); guidanceOverlay.hide()
        approvedScreenID = nil; capturedScreen = nil; localScreenText = ""; capturingScreen = true; error = nil
        execution = Task {
            defer { capturingScreen = false; execution = nil }
            do { let screen = try await ScreenContext.capture(displayChoice: screenDisplayChoice); try Task.checkCancellation(); capturedScreen = screen; openCommandCenter(page: .companion) }
            catch { if !(error is CancellationError) { self.error = error.localizedDescription }; openCommandCenter(page: .companion) }
        }
    }

    func clearScreenContext() { if capturingScreen { execution?.cancel() }; capturedScreen = nil; approvedScreenID = nil; localScreenText = "" }

    func readScreenLocally() {
        guard let screen = capturedScreen, !busy, !capturingScreen, pending == nil else { return }
        capturingScreen = true
        execution = Task {
            defer { capturingScreen = false; execution = nil }
            do { let text = try await ScreenContext.readText(screen); try Task.checkCancellation(); if capturedScreen?.id == screen.id { localScreenText = text } }
            catch { self.error = error.localizedDescription }
        }
    }

    func askUsingApprovedScreen() {
        guard let screen = capturedScreen, approvedScreenID == screen.id, !busy, !capturingScreen else { error = "Review this screenshot and choose Use this screen first."; return }
        guard useOpenAI, keyConfigured else { error = "Connect OpenAI in Settings to analyze a screen. Local text extraction does not need an API key."; return }
        let question = guideQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { error = "Ask a question about the screen first."; return }
        guard question.count <= 16000 else { error = "Please keep a request under 16,000 characters."; return }
        approvedScreenID = nil; busy = true; error = nil
        execution = Task {
            defer { busy = false; execution = nil; capturedScreen = nil }
            do {
                guard let key = try KeychainStore.load() else { throw Newtv1Failure("Save an OpenAI key in Settings first.") }
                let result = try await OpenAIBrain().guide(question, jpeg: screen.jpeg, model: openAIModel, key: key)
                try Task.checkCancellation()
                lastGuidance = result; guideDisplayID = screen.displayID; guideFrame = screen.frame
                brainAnswers.insert(BrainAnswer(question: question, markdown: result.answer), at: 0); brainAnswers = Array(brainAnswers.prefix(30))
                saveConversationHistory()
                if speakAnswers { speakAnswer(result.answer) }
                openCommandCenter(page: .companion)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    func generateDiagram(_ prompt: String) {
        guard !busy, !capturingScreen, pending == nil else { return }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= 8000 else { error = "Describe a diagram in 1–8,000 characters."; return }
        guard useOpenAI, keyConfigured else { error = "Connect the OpenAI brain to generate a diagram. The example and imported diagrams work locally."; return }
        busy = true; error = nil
        execution = Task {
            defer { busy = false; execution = nil }
            do {
                guard let key = try KeychainStore.load() else { throw Newtv1Failure("Save an API key in Settings first.") }
                let result = try await OpenAIBrain().diagram(prompt, model: openAIModel, key: key)
                try Task.checkCancellation(); diagram = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    func showLastGuidance() {
        guard let result = lastGuidance, let displayID = guideDisplayID else { return }
        guidanceOverlay.show(result.highlights, displayID: displayID, frame: guideFrame, color: NSColor(notch.tint))
    }
    func hideGuidance() { guidanceOverlay.hide() }

    func speakAnswer(_ answer: String) {
        resumeListeningAfterSpeech = speech.isListening
        speech.stop()
        speaker.speak(answer, voiceID: voiceID, rate: voiceRate)
    }

    private func beginAgentJob(_ goal: String) -> UUID {
        let job = AgentJob(goal: goal)
        agentJobs.insert(job, at: 0); agentJobs = Array(agentJobs.prefix(25))
        return job.id
    }
    private func updateJob(_ id: UUID?, status: AgentJob.Status, detail: String, steps: [String]? = nil) {
        guard let id, let index = agentJobs.firstIndex(where: { $0.id == id }) else { return }
        agentJobs[index].status = status; agentJobs[index].detail = detail
        if let steps { agentJobs[index].steps = steps }
    }

    func previewAgentControls() {
        do { guidedObservationPreview = try automation.controlObservation() }
        catch { self.error = error.localizedDescription }
    }
    func startGuidedAgent(_ goal: String) {
        guard !busy, !capturingScreen, pending == nil else { return }
        guard useOpenAI, keyConfigured else { error = "Connect OpenAI before starting a guided agent."; return }
        let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, goal.count <= 8000 else { error = "Describe a task in 1–8,000 characters."; return }
        guidedJobID = beginAgentJob(goal); guidedGoal = goal; guidedRequests = 0
        requestGuidedStep()
    }
    func replanGuidedAgent() {
        guard !busy, !capturingScreen, pending == nil, guidedJobID != nil else { return }
        requestGuidedStep()
    }
    private func requestGuidedStep() {
        guard let jobID = guidedJobID else { return }
        guard guidedRequests < 8 else { updateJob(jobID, status: .paused, detail: "The eight-observation budget is exhausted. Inspect the result and start a new task if needed."); guidedJobID = nil; return }
        guard useOpenAI, keyConfigured else { updateJob(jobID, status: .blocked, detail: "OpenAI is not connected."); return }
        let observation: String
        do { observation = try automation.controlObservation(); guidedObservationPreview = observation }
        catch { self.error = error.localizedDescription; updateJob(jobID, status: .blocked, detail: error.localizedDescription); return }
        guidedRequests += 1; busy = true; error = nil
        let goal = guidedGoal
        let completed = agentJobs.first(where: { $0.id == jobID })?.trace.suffix(8).joined(separator: "\n") ?? ""
        updateJob(jobID, status: .planning, detail: "Observing current controls · request \(guidedRequests)/8. No new action has started.")
        execution = Task {
            defer { busy = false; execution = nil }
            do {
                guard let key = try KeychainStore.load() else { throw Newtv1Failure("Save an API key first.") }
                let decision = try await OpenAIBrain().decide(goal + "\nLocal execution log for this task:\n" + completed, model: openAIModel, key: key, target: targetName, workflows: [], observation: observation)
                try Task.checkCancellation()
                guard guidedJobID == jobID else { return }
                if decision.intent == "actions" {
                    let plan = try decision.actionPlan(transcript: goal, workflows: [])
                    guard plan.actions.count == 1 else { throw Newtv1Failure("Guided agents must propose one direct action at a time.") }
                    pending = plan; pendingJobID = jobID
                    updateJob(jobID, status: .review, detail: "Review the next step based on the latest controls.", steps: plan.actions.map(\.summary))
                    openCommandCenter(page: .control)
                } else if decision.intent == "answer", !decision.answer.isEmpty {
                    updateJob(jobID, status: .paused, detail: "Agent stopped. Inspect the outcome before marking it complete.\n" + decision.answer)
                    notices.add("Guided task stopped", detail: String(decision.answer.prefix(400)))
                    guidedJobID = nil
                    // The model's explanation is shown; a provider statement is not a verified result.
                } else { throw Newtv1Failure("The guided agent needs more information. Start a clearer task.") }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription; updateJob(jobID, status: .failed, detail: error.localizedDescription) }
            }
        }
    }

    func markJobComplete(_ id: UUID) {
        updateJob(id, status: .complete, detail: "Marked complete by you after inspecting the result.")
        if guidedJobID == id { guidedJobID = nil }
    }

    func reviewRecovery(_ job: AgentJob) {
        guard !busy, !capturingScreen, pending == nil, !job.remaining.isEmpty else { return }
        pending = CommandPlan(transcript: "Continue: " + job.goal, actions: job.remaining, requiresReview: true)
        pendingJobID = job.id
        updateJob(job.id, status: .review, detail: "Review remaining steps. The failed action may have partially completed; decline and submit corrected commands if work has already happened.")
        openCommandCenter(page: .control)
    }
    private var tasksURL: URL { historyURL.deletingLastPathComponent().appendingPathComponent("tasks.json") }
    private func saveTaskHistory() {
        guard rememberConversations else { return }
        do {
            try FileManager.default.createDirectory(at: tasksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(agentJobs.prefix(25))).write(to: tasksURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tasksURL.path)
        } catch { /* Keep the current task usable when local history cannot be written. */ }
    }
    private func loadTaskHistory() {
        guard rememberConversations, let size = try? tasksURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
              let data = try? Data(contentsOf: tasksURL), var jobs = try? JSONDecoder().decode([AgentJob].self, from: data) else { return }
        jobs = Array(jobs.prefix(25))
        for i in jobs.indices where [.planning, .running, .review].contains(jobs[i].status) {
            jobs[i].status = .cancelled; jobs[i].detail = "Interrupted by app restart. Inspect the app and review remaining steps before continuing."
        }
        agentJobs = jobs
    }

    private var historyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Newtv1", isDirectory: true).appendingPathComponent("conversations.json")
    }
    private func conversationContext() -> [ConversationTurn] {
        brainAnswers.prefix(6).reversed().flatMap { [ConversationTurn(role: "user", content: $0.question), ConversationTurn(role: "assistant", content: $0.markdown)] }
    }
    private func loadConversationHistory() {
        guard rememberConversations, let size = try? historyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2_000_000,
              let data = try? Data(contentsOf: historyURL), let answers = try? JSONDecoder().decode([BrainAnswer].self, from: data) else { return }
        brainAnswers = Array(answers.prefix(30))
    }
    private func saveConversationHistory() {
        guard rememberConversations else { return }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(brainAnswers.prefix(30))).write(to: historyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        } catch { self.error = "Could not save conversation history on this Mac." }
    }
    func clearConversationHistory() {
        let alert = NSAlert(); alert.messageText = "Clear Newtv1 conversation history?"
        alert.informativeText = "This removes current answers and the locally saved history. It does not delete your workflows or API key."
        alert.addButton(withTitle: "Clear history"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        brainAnswers.removeAll(); agentJobs.removeAll(); lastGuidance = nil; guidanceOverlay.hide()
        if FileManager.default.fileExists(atPath: tasksURL.path) { try? FileManager.default.removeItem(at: tasksURL) }
        if FileManager.default.fileExists(atPath: historyURL.path) { do { try FileManager.default.removeItem(at: historyURL) } catch { self.error = "Could not remove saved history." } }
    }
}

final class GlobalHotkey {
    var onToggle: (() -> Void)?
    var onRelease: (() -> Void)?
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    func register() -> Bool {
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
            if let event, GetEventKind(event) == UInt32(kEventHotKeyReleased) { hotkey.onRelease?() }
            else { hotkey.onToggle?() }
            return noErr
        }, 2, &specs, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: 0x4E545631, id: 1)
        return installed == noErr && RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotkey) == noErr
    }
    deinit { if let hotkey { UnregisterEventHotKey(hotkey) }; if let handler { RemoveEventHandler(handler) } }
}

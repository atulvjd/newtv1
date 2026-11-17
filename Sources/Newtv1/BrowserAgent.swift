import SwiftUI
import Combine
import Newtv1Core
import AppKit
import UniformTypeIdentifiers
private typealias BrowserAgentState<T> = SwiftUI.State<T>

@MainActor
final class BrowserAgent: ObservableObject {
    @Published private(set) var state: BrowserBridgeState?
    @Published private(set) var pending: BrowserCommand?
    @Published private(set) var explanation = ""
    @Published private(set) var goal = ""
    @Published private(set) var log: [String] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "Connect one tab using the extension, then refresh here."
    @Published private(set) var uploadName = ""
    @Published var runPolicy: BrowserRunPolicy = .review
    private var uploadData: Data?
    private var stagedUpload: UUID?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var approval: (session: UUID, provider: AIProvider)?
    private var requests = 0
    private var provider: AIProvider?
    private var historyURL: URL { BrowserBridge.directory.deletingLastPathComponent().appendingPathComponent("browser-task.json") }
    var connected: Bool { state?.live == true && state?.snapshot != nil }

    init() {
        let files = (try? FileManager.default.contentsOfDirectory(at: BrowserBridge.directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.prefix(1000) where file.lastPathComponent.hasPrefix("upload-") && file.pathExtension == "json" {
            if let grant = try? BrowserBridge.read(file.lastPathComponent, as: BrowserUpload.self), grant.expiresAt <= Date() {
                try? FileManager.default.removeItem(at: file)
                try? FileManager.default.removeItem(at: file.deletingPathExtension().appendingPathExtension("data"))
            }
        }
        guard UserDefaults.standard.bool(forKey: "rememberConversations"),
              let size = try? historyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 500000,
              let data = try? Data(contentsOf: historyURL), let saved = try? JSONDecoder().decode(BrowserTaskMemory.self, from: data) else { return }
        let bounded = BrowserTaskMemory(goal: saved.goal, log: saved.log, provider: saved.provider)
        goal = bounded.goal; log = bounded.log; provider = bounded.provider
        status = "Restored task. Reconnect a tab and approve sharing before continuing."
    }
    func saveHistory() {
        guard UserDefaults.standard.bool(forKey: "rememberConversations"), let provider else { return }
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(BrowserTaskMemory(goal: goal, log: log, provider: provider)).write(to: historyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
        } catch { status = "Could not save task history; this session is still available." }
    }
    func clearHistory() {
        stop(); goal = ""; log = []; explanation = ""; provider = nil
        try? FileManager.default.removeItem(at: historyURL)
    }
    func resume(model: AppModel) {
        guard !busy, pending == nil, !goal.isEmpty, provider == model.aiProvider else { status = "Select this task's original provider and finish pending work first."; return }
        refresh(); guard connected, let state else { status = "Connect a tab first."; return }
        approval = (state.session, model.aiProvider); requests = 0; next(model: model)
    }

    func refresh() {
        state = try? BrowserBridge.read("state.json", as: BrowserBridgeState.self)
        if !connected, !busy { status = state?.message ?? "Connect one tab using the extension." }
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil; pending = nil; approval = nil; busy = false
        BrowserBridge.clearCommand()
        clearUpload()
        status = "Stopped. An action already dispatched may have completed; inspect the page."
    }
    func chooseUpload() {
        guard !busy, pending?.action.kind == .upload else { return }
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        picker.message = "Choose one file up to 20 MB. Review the filename and destination before attaching. The website may upload as soon as it is attached."
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CommandError.invalid("Choose a regular file.") }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: BrowserUpload.maximumSize + 1) ?? Data()
            guard data.count <= BrowserUpload.maximumSize else { throw CommandError.invalid("Choose a file up to 20 MB.") }
            uploadData = data; uploadName = url.lastPathComponent
        } catch { status = error.localizedDescription }
    }
    private func clearUpload() {
        uploadData = nil; uploadName = ""
        if let id = stagedUpload {
            for suffix in [".json", ".data"] { try? FileManager.default.removeItem(at: BrowserBridge.directory.appendingPathComponent("upload-" + id.uuidString + suffix)) }
        }
        stagedUpload = nil
    }
    func start(_ text: String, model: AppModel) {
        guard !busy, !model.busy, !model.capturingScreen, model.pending == nil else { return }
        refresh()
        guard let state, connected else { status = "Connect a tab and refresh before starting."; return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 8000 else { status = "Describe a task in 1–8,000 characters."; return }
        guard model.useOpenAI, model.keyConfigured else { status = "Connect your AI provider in Settings."; return }
        stop(); goal = text; log = []; requests = 0
        provider = model.aiProvider; saveHistory()
        approval = (state.session, model.aiProvider)
        next(model: model)
    }
    func followUp(_ text: String, model: AppModel) {
        guard !busy, pending == nil, !goal.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard goal.count + text.count <= 16000 else { status = "Start a new task; this task's context is full."; return }
        goal += "\nUser follow-up: " + text
        saveHistory()
        requests = 0
        next(model: model)
    }
    func next(model: AppModel) {
        guard !busy, pending == nil, !model.busy, !model.capturingScreen, model.pending == nil else { return }
        refresh()
        guard connected, let snapshot = state?.snapshot, let approval, approval.session == snapshot.session, approval.provider == model.aiProvider else {
            status = "Connection or provider changed. Review and start the task again to share context."; return
        }
        guard requests < 40 else { status = "Paused after 40 observations. Inspect the result, then send a follow-up to continue."; return }
        requests += 1; busy = true; status = "Observing page and planning step \(requests)/40…"
        let token = generation
        task = Task {
            var automaticallyContinue = false
            defer {
                if generation == token {
                    busy = false; task = nil
                    if automaticallyContinue { approve(model: model) }
                }
            }
            do {
                let key = try await model.aiCredential(for: model.aiProvider)
                let step = try await OpenAIBrain(provider: model.aiProvider).browserStep(goal, snapshot: snapshot, log: log, model: model.aiModel, key: key, preferences: model.responsePreferences)
                try Task.checkCancellation(); guard generation == token else { return }
                explanation = step.explanation
                if let action = try step.action(in: snapshot) {
                    pending = try BrowserCommand(snapshot: snapshot, action: action)
                    status = "Review the next action. Nothing has run yet."
                    automaticallyContinue = runPolicy.allows(action)
                } else {
                    status = step.status == "done" ? "Planner reports completion. Inspect the page to confirm." : "Needs your input."
                    appendLog(step.explanation)
                }
            } catch { if generation == token { status = error.localizedDescription } }
        }
    }
    func approve(model: AppModel) {
        guard !busy, !model.busy, !model.capturingScreen, model.pending == nil, let proposed = pending else { return }
        refresh()
        do {
            guard connected, let snapshot = state?.snapshot else { throw CommandError.invalid("The browser disconnected.") }
            guard approval?.provider == model.aiProvider else { throw CommandError.invalid("Provider changed. Start this task again.") }
            // Approval may take longer than the delivery TTL. Rebind only to the exact reviewed document/revision.
            guard proposed.session == snapshot.session, proposed.document == snapshot.document, proposed.revision == snapshot.revision else { throw CommandError.invalid("The page changed since review. Observe a new step.") }
            let command = try BrowserCommand(snapshot: snapshot, action: proposed.action)
            if command.action.kind == .upload {
                guard let data = uploadData, !uploadName.isEmpty else { throw CommandError.invalid("Choose and review a file first.") }
                let mime = UTType(filenameExtension: (uploadName as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                let grant = try BrowserUpload(command: command, fileName: uploadName, size: data.count, mimeType: mime)
                // Write the grant first so the directory is owner-only before staging bytes.
                stagedUpload = command.id
                try BrowserBridge.write(grant, to: "upload-" + command.id.uuidString + ".json")
                let url = BrowserBridge.directory.appendingPathComponent("upload-" + command.id.uuidString + ".data")
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            try BrowserBridge.write(command, to: "command.json")
            pending = nil; busy = true; status = "Waiting for the connected tab…"
            let token = generation
            task = Task {
                do {
                    let deadline = Date().addingTimeInterval(command.action.kind == .upload ? 120 : 24)
                    while Date() < deadline {
                        try Task.checkCancellation(); guard generation == token else { return }
                        refresh()
                        if let result = state?.result, result.id == command.id {
                            clearUpload()
                            appendLog(command.action.summary(in: snapshot) + "\n" + result.message)
                            busy = false; task = nil
                            if result.ok, connected { next(model: model) }
                            else { status = result.message + " Inspect the page, then observe again." }
                            return
                        }
                        try await Task.sleep(nanoseconds: 250_000_000)
                    }
                    throw CommandError.invalid("No action receipt arrived. It may have completed. Inspect before continuing; it will not be replayed.")
                } catch {
                    if generation == token { BrowserBridge.clearCommand(); clearUpload(); busy = false; task = nil; status = error.localizedDescription }
                }
            }
        } catch { pending = nil; clearUpload(); status = error.localizedDescription }
    }
    func decline() { pending = nil; clearUpload(); status = "Action declined. No further step will run until you ask." }
    private func appendLog(_ value: String) { log.append(String(value.prefix(3000))); log = Array(log.suffix(30)); saveHistory() }
}

struct BrowserAgentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var agent: BrowserAgent
    private var prompt: String { model.browserTaskInput }
    @BrowserAgentState private var consent = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Browser tasks", systemImage: "cursorarrow.click.2").font(.system(size: 18, weight: .medium)); Spacer(); Text(agent.connected ? "CONNECTED" : "DISCONNECTED").font(.system(size: 10, design: .monospaced)).foregroundStyle(agent.connected ? WorkspaceTheme.accent : WorkspaceTheme.secondary); Button("Refresh") { agent.refresh() } }
            if let snapshot = agent.state?.snapshot {
                Text(snapshot.page.title).font(.system(size: 14, weight: .medium))
                Text(snapshot.page.url).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary).textSelection(.enabled)
                DisclosureGroup("Preview the text and controls shared with AI") {
                    ScrollView { Text(preview(snapshot)).font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 200)
                }
            }
            Text("Connect one tab from the extension. Each proposed click or edit has a review below. Newt observes the result before proposing the next step. A new website needs reconnection.").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
            Toggle("Share this tab's visible text and control labels with \(model.aiProvider.title) for this task", isOn: $consent).toggleStyle(WorkspaceToggleStyle()).font(.system(size: 12))
            Picker("Task continuation", selection: $agent.runPolicy) { ForEach(BrowserRunPolicy.allCases) { Text($0.rawValue).tag($0) } }.disabled(agent.busy)
            TextField("Describe the browser task…", text: $model.browserTaskInput).textFieldStyle(WorkspaceFieldStyle())
            HStack {
                Button("Start browser task") { agent.start(prompt, model: model); model.browserTaskInput = "" }.disabled(!consent || !agent.connected || agent.busy || prompt.isEmpty || model.busy)
                if !agent.goal.isEmpty { Button("Send follow-up") { agent.followUp(prompt, model: model); model.browserTaskInput = "" }.disabled(!consent || agent.busy || agent.pending != nil || prompt.isEmpty); Button("Continue task") { agent.resume(model: model) }.disabled(!consent || agent.busy || agent.pending != nil) }
                Button("Stop") { agent.stop() }.foregroundStyle(.orange)
            }.buttonStyle(WorkspaceButtonStyle())
            Text(agent.status).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
            if !agent.goal.isEmpty { Text("Goal: " + agent.goal).font(.system(size: 12)).textSelection(.enabled) }
            if let command = agent.pending, let snapshot = agent.state?.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    Text(command.action.summary(in: snapshot)).font(.system(size: 15, weight: .medium)).textSelection(.enabled)
                    Text(agent.explanation).font(.system(size: 12)).textSelection(.enabled)
                    Text("Destination: " + snapshot.page.url).font(.system(size: 11)).foregroundStyle(.orange)
                    if command.action.kind == .upload {
                        Button("Choose file…") { agent.chooseUpload() }.buttonStyle(WorkspaceButtonStyle())
                        if !agent.uploadName.isEmpty { Text("File: " + agent.uploadName).font(.system(size: 13, weight: .medium)) }
                        Text("Attaching exposes this file to this website, which may upload immediately. File contents are not sent to the AI provider.").font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    HStack { Button(command.action.kind == .upload ? "Approve file attachment" : "Approve this action") { agent.approve(model: model) }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black).disabled(!consent || !agent.connected || (command.action.kind == .upload && agent.uploadName.isEmpty)); Button("Not now") { agent.decline() }.buttonStyle(WorkspaceButtonStyle()) }
                }.padding(16).background(WorkspaceTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else if !agent.explanation.isEmpty { Text(agent.explanation).font(.system(size: 12)).textSelection(.enabled) }
            if !agent.log.isEmpty { DisclosureGroup("Task observations") { ForEach(Array(agent.log.enumerated()), id: \.offset) { _, line in Text(line).font(.system(size: 11)).textSelection(.enabled).padding(.vertical, 5) } } }
        }
        .padding(20).workspaceCard()
        .onAppear { agent.refresh() }
        .onReceive(timer) { _ in agent.refresh() }
        .onChange(of: model.aiProvider) { _ in agent.stop(); consent = false }
        .onChange(of: consent) { if !$0 { agent.stop() } }
    }
    private func preview(_ snapshot: BrowserSnapshot) -> String {
        let controls = snapshot.controls.map { "\($0.id) · \($0.role) · \($0.label)" + (($0.options ?? []).isEmpty ? "" : " · options: " + ($0.options ?? []).joined(separator: ", ")) }.joined(separator: "\n")
        return snapshot.page.text + "\n\nCONTROLS\n" + controls
    }
}

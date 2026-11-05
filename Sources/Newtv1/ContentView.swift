import SwiftUI
import Newtv1Core

// Explicitly reference the property wrapper type: newer SDKs also export a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private let accent = Color(red: 0.79, green: 0.97, blue: 0.43)
private let surface = Color(red: 0.075, green: 0.081, blue: 0.095)
private let muted = Color(red: 0.52, green: 0.55, blue: 0.60)

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    @ViewState private var newWorkflow = false
    @ViewState private var editingWorkflow: Workflow?
    @ViewState private var apiKey = ""
    @ViewState private var keyMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let error = model.error {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                Text(error).font(.system(size: 13)).textSelection(.enabled)
                                Spacer()
                                Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            }.padding(15).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                        switch model.page {
                        case .control: commandCenter
                        case .brain: brain
                        case .workflows: workflows
                        case .guide: guide
                        case .settings: settings
                        }
                    }.padding(30)
                }
                footer
            }
        }
        .background(Color(red: 0.043, green: 0.047, blue: 0.058))
        .tint(accent)
        .environment(\.openURL, OpenURLAction { url in
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction
        })
        .sheet(item: $model.pending) { plan in confirmation(plan) }
        .sheet(isPresented: $newWorkflow) { WorkflowEditor(model: model, workflow: nil) }
        .sheet(item: $editingWorkflow) { workflow in WorkflowEditor(model: model, workflow: workflow) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 26, weight: .bold)).foregroundStyle(accent)
                Text("Newtv1").font(.system(size: 23, weight: .bold, design: .rounded)).tracking(-1)
                Text("LOCAL").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(muted).padding(.horizontal, 5).padding(.vertical, 4).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12)))
            }.padding(.top, 38).padding(.bottom, 42).padding(.horizontal, 24)
            Text("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(muted).padding(.horizontal, 25).padding(.bottom, 14)
            ForEach(AppPage.allCases, id: \.self) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.icon).frame(width: 18)
                        Text(page.rawValue).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer()
                        if page == model.page { Circle().fill(accent).frame(width: 5, height: 5) }
                    }.foregroundStyle(page == model.page ? accent : Color.white.opacity(0.56)).padding(.horizontal, 14).padding(.vertical, 13)
                        .background(page == model.page ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Circle().fill(speech.isListening ? accent : muted).frame(width: 6, height: 6); Text(speech.isListening ? "MICROPHONE ACTIVE" : "READY WHEN YOU ARE").font(.system(size: 9, weight: .semibold)).tracking(1) }
                Text("Your Mac.\nYour command.").font(.system(size: 20, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
                HStack { Text("⌥"); Text("space") }.font(.system(size: 11, design: .monospaced)).foregroundStyle(muted).padding(7).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1)))
                Text("Toggle voice from any app").font(.system(size: 10)).foregroundStyle(muted)
            }.padding(19).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).padding(14)
            HStack { Text("NEWTV1 FOR macOS"); Spacer(); Text("v0.2") }.font(.system(size: 9, design: .monospaced)).foregroundStyle(muted.opacity(0.7)).padding(22)
        }.background(Color.white.opacity(0.012))
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) { Text("Workspace").foregroundStyle(muted); Text("/").foregroundStyle(muted.opacity(0.4)); Text(model.page.rawValue) }.font(.system(size: 12))
            Spacer()
            Image(systemName: "laptopcomputer").foregroundStyle(muted)
            Text(Host.current().localizedName ?? "This Mac").font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
        }.padding(.horizontal, 30).frame(height: 62).overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }

    private var commandCenter: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Less clicking. More doing.").font(.system(size: 30, weight: .semibold)).tracking(-1)
                    Text("Speak your next move. Newtv1 takes it from here.").font(.system(size: 13)).foregroundStyle(muted)
                }
                Spacer()
                Label(speech.isListening ? "Listening" : "Standby", systemImage: "circle.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(speech.isListening ? accent : muted).padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.04), in: Capsule())
            }
            VStack(spacing: 0) {
                HStack {
                    Label("VOICE CONTROL", systemImage: "waveform").font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(muted)
                    Spacer()
                    Text(model.allowNetwork ? "APPLE SPEECH" : "ON-DEVICE SPEECH").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                }.padding(20)
                HStack(spacing: 28) {
                    VoiceOrb(active: speech.isListening, level: speech.level).frame(width: 180, height: 180)
                    VStack(alignment: .leading, spacing: 13) {
                        Text(model.busy ? "Making it happen." : speech.isListening ? "I’m listening." : "Your voice is the shortcut.").font(.system(size: 26, weight: .medium)).tracking(-0.6)
                        Text(speech.isListening ? (model.wakeWord ? "Start with “Newtv1”, then say a command." : "Say a command, then pause to execute.") : "Open apps, arrange windows, click controls,\nand build routines with a few words.")
                            .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            Button { model.toggleListening() } label: {
                                Label(model.speechStarting ? "Starting…" : speech.isListening ? "Stop listening" : "Start listening", systemImage: speech.isListening ? "stop.fill" : "mic.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 11).background(accent, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).disabled(model.speechStarting)
                            Text("⌥ Space").font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                        }.padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 20).padding(.bottom, 24)
                HStack(spacing: 10) {
                    Image(systemName: "quote.bubble").foregroundStyle(accent.opacity(0.65))
                    Text(speech.transcript.isEmpty ? "Try “Newtv1, open Safari then left half”" : speech.transcript).font(.system(size: 12)).foregroundStyle(speech.transcript.isEmpty ? muted : .white).lineLimit(2)
                    Spacer()
                    if speech.isListening { WaveMeter(level: speech.level) }
                }.padding(17).background(Color.black.opacity(0.14))
            }.background(surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07)))
            HStack(spacing: 12) {
                Image(systemName: "terminal").foregroundStyle(accent)
                TextField("Or type a command…", text: $model.input).textFieldStyle(.plain).font(.system(size: 13)).onSubmit { model.submit() }.disabled(model.busy || model.pending != nil)
                if model.busy {
                    Button("Stop") { model.stop() }.foregroundStyle(.orange).buttonStyle(.plain)
                } else {
                    Button { model.submit() } label: { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black).frame(width: 30, height: 30).background(accent, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain).disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.padding(12).background(surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.09)))
            HStack(spacing: 12) {
                quickAction("App control", "Open Safari", "app.badge", "open Safari")
                quickAction("Screen navigation", "Show numbers", "number.square", "show numbers")
                quickAction("Window management", "Split it left", "rectangle.lefthalf.inset.filled", "left half")
            }
            activityList
        }
    }

    private func quickAction(_ category: String, _ title: String, _ icon: String, _ command: String) -> some View {
        Button { model.input = command } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Image(systemName: icon).font(.system(size: 17)).foregroundStyle(accent.opacity(0.85)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(muted) }
                VStack(alignment: .leading, spacing: 5) { Text(category).font(.system(size: 9)).foregroundStyle(muted); Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("Recent activity").font(.system(size: 15, weight: .medium)); Text("\(model.activities.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted); Spacer(); if !model.activities.isEmpty { Button("Clear") { model.activities.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(muted).disabled(model.busy) } }
            if model.activities.isEmpty {
                HStack(spacing: 12) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 20)).foregroundStyle(muted); VStack(alignment: .leading, spacing: 5) { Text("A little less work starts here.").font(.system(size: 12)); Text("Your commands and their results will appear here.").font(.system(size: 11)).foregroundStyle(muted) }; Spacer() }.padding(22).frame(maxWidth: .infinity).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [4])))
            }
            ForEach(model.activities) { activity in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: activity.state == .success ? "checkmark.circle.fill" : activity.state == .running ? "arrow.triangle.2.circlepath" : activity.state == .cancelled ? "stop.circle" : "exclamationmark.circle").foregroundStyle(activity.state == .failed ? .orange : accent).font(.system(size: 15)).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) { Text(activity.command).font(.system(size: 12, weight: .medium)); Text(activity.detail).font(.system(size: 11)).foregroundStyle(muted).lineSpacing(3).textSelection(.enabled) }
                    Spacer(); Text(activity.date, style: .time).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                }.padding(15).background(surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var workflows: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { title("One phrase. A whole routine.", "Build sequences you can run with “Newtv1, run focus mode”."); Spacer(); Button { newWorkflow = true } label: { Label("New workflow", systemImage: "plus") }.buttonStyle(.borderedProminent).foregroundStyle(.black) }
            ForEach(model.workflows) { workflow in
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent); Text(workflow.name).font(.system(size: 18, weight: .medium)); Spacer(); Button("Edit") { editingWorkflow = workflow }.buttonStyle(.bordered); Button { model.submit("run \(workflow.name)") } label: { Label("Run", systemImage: "play.fill") }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(model.busy) }
                    Text(workflow.commands).font(.system(size: 12, design: .monospaced)).foregroundStyle(muted).lineSpacing(6).textSelection(.enabled)
                    HStack { Text("SAY “NEWTV1, RUN \(workflow.name.uppercased())”").font(.system(size: 9, design: .monospaced)).foregroundStyle(accent.opacity(0.7)); Spacer(); Button(role: .destructive) { model.workflows.removeAll { $0.id == workflow.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("Delete workflow") }
                }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 14))
            }
            if model.workflows.isEmpty { Text("Create your first workflow to combine commands into a routine.").foregroundStyle(muted) }
            Text("One command per line. Nested workflows are supported. Shell steps always require an on-screen review before execution.").font(.system(size: 12)).foregroundStyle(muted)
        }
    }

    private var brain: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("A little more brainpower.", "Ask a question, look something up, or describe what you want your Mac to do.")
            HStack(spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(accent)
                TextField("Ask anything…", text: $model.input).textFieldStyle(.plain).onSubmit { model.requestBrain(model.input, mode: .answer) }.disabled(model.busy)
                if model.busy { Button("Stop") { model.stop() }.buttonStyle(.plain).foregroundStyle(.orange) }
                else {
                    Button("Search web") { model.requestBrain(model.input, mode: .search) }.buttonStyle(.bordered).disabled(!model.allowWebSearch)
                    Button("Ask") { model.requestBrain(model.input, mode: .answer) }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                }
            }.padding(16).background(surface, in: RoundedRectangle(cornerRadius: 12))
            if !model.keyConfigured { Button("Connect OpenAI in Settings") { model.page = .settings }.buttonStyle(.bordered) }
            if model.brainAnswers.isEmpty {
                Text("Try “ask why the sky is blue” or “research the latest Mac news” in the command center. Voice works too: “New TV One, ask …”. Answers stay in memory for this session.").font(.system(size: 13)).foregroundStyle(muted).lineSpacing(5)
            }
            ForEach(model.brainAnswers) { answer in
                VStack(alignment: .leading, spacing: 16) {
                    Text(answer.question).font(.system(size: 17, weight: .medium)).textSelection(.enabled)
                    Divider()
                    Text((try? AttributedString(markdown: answer.markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(answer.markdown))
                        .font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).tint(accent)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("A few words go a long way.", "Use these phrases as written. Add “Newtv1” first when wake phrase mode is on.")
            ForEach(Array(commandGroups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 14) {
                    Text(group.0).font(.system(size: 16, weight: .medium))
                    ForEach(group.1, id: \.self) { command in HStack { Text(command).font(.system(size: 12, design: .monospaced)).foregroundStyle(muted); Spacer(); Button { model.input = command; model.page = .control } label: { Image(systemName: "arrow.up.left") }.buttonStyle(.plain).foregroundStyle(accent).help("Use this command") } }
                }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("“Type”, “write”, “dictate”, “search”, and “shell” preserve everything after them as literal content. Use separate workflow lines when combining these with other steps. Numbers may be spoken as words. Controls depend on what each app exposes to Accessibility.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Set up your command space.", "macOS permissions keep you in charge of what Newtv1 can do.")
            VStack(alignment: .leading, spacing: 18) {
                HStack { Label("OpenAI brain", systemImage: "sparkles").font(.system(size: 16, weight: .medium)); Spacer(); Text(model.keyConfigured ? "KEY IN KEYCHAIN" : "NOT CONNECTED").font(.system(size: 9, design: .monospaced)).foregroundStyle(model.keyConfigured ? accent : muted) }
                Toggle("Use OpenAI for questions and natural-language actions", isOn: $model.useOpenAI).toggleStyle(.switch).disabled(!model.keyConfigured)
                Toggle("Allow web search for answers", isOn: $model.allowWebSearch).toggleStyle(.switch)
                HStack { Text("Model").font(.system(size: 12)); TextField("gpt-5.4-mini", text: $model.openAIModel).textFieldStyle(.roundedBorder) }
                HStack {
                    SecureField(model.keyConfigured ? "Replace API key…" : "OpenAI API key…", text: $apiKey).textFieldStyle(.roundedBorder)
                    Button("Save to Keychain") { do { try model.saveOpenAIKey(apiKey); apiKey = ""; keyMessage = "Key saved securely." } catch { apiKey = ""; keyMessage = error.localizedDescription } }.buttonStyle(.bordered).disabled(apiKey.isEmpty)
                    if model.keyConfigured { Button("Remove key") { do { try model.removeOpenAIKey(); keyMessage = "Key removed." } catch { keyMessage = error.localizedDescription } }.buttonStyle(.bordered) }
                }
                if let keyMessage { Text(keyMessage).font(.system(size: 11)).foregroundStyle(muted) }
                Text("Questions and searches are sent to OpenAI; action planning also sends the target app and workflow names. No screenshots or audio are sent by this feature. API requests and web searches use your API credits. AI action plans require review; generated shell commands are blocked.").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
            }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(spacing: 0) {
                permissionRow("Accessibility", "Click controls, type, send shortcuts, and move windows.", model.accessibility) { model.requestAccessibility() }
                Divider().overlay(Color.white.opacity(0.04))
                permissionRow("Microphone", "Hear your commands while listening is enabled.", model.microphone) { model.openPrivacy("Microphone") }
                Divider().overlay(Color.white.opacity(0.04))
                permissionRow("Speech recognition", "Turn speech into commands using Apple’s recognizer.", model.speechPermission) { model.openPrivacy("SpeechRecognition") }
                Divider().overlay(Color.white.opacity(0.04))
                HStack { VStack(alignment: .leading, spacing: 5) { Text("Screen Recording").font(.system(size: 13, weight: .medium)); Text("Only needed for the screenshot command.").font(.system(size: 11)).foregroundStyle(muted) }; Spacer(); Button("Open settings") { model.openPrivacy("ScreenCapture") }.buttonStyle(.bordered) }.padding(20)
            }.background(surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 22) {
                Toggle(isOn: $model.wakeWord) { VStack(alignment: .leading, spacing: 5) { Text("Require “New TV One” before each command").font(.system(size: 13, weight: .medium)); Text("Say “New TV One” or “Hey New TV One”. The transcript may also spell it Newtv1.").font(.system(size: 11)).foregroundStyle(muted) } }.toggleStyle(.switch)
                Divider()
                Toggle(isOn: $model.allowNetwork) { VStack(alignment: .leading, spacing: 5) { Text("Allow Apple network speech recognition").font(.system(size: 13, weight: .medium)); Text("Off by default. Turning this on may send audio to Apple. Changing it stops listening.").font(.system(size: 11)).foregroundStyle(muted) } }.toggleStyle(.switch)
            }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: $model.useLocalPlanner) { VStack(alignment: .leading, spacing: 5) { Text("Natural language with Ollama").font(.system(size: 13, weight: .medium)); Text("Send unrecognized requests to your local Ollama server. Every generated plan requires an on-screen review.").font(.system(size: 11)).foregroundStyle(muted) } }.toggleStyle(.switch)
                HStack { Text("Installed model").font(.system(size: 12)); TextField("Your local model name", text: $model.localModel).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced)) }
                Text("Requires Ollama running at 127.0.0.1:11434 with a downloaded local model. Newtv1 sends the request, target app name, and workflow names. The model cannot see your screen. AI-generated shell commands are blocked.").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
            }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 10) {
                Label("Local by default", systemImage: "lock.shield").font(.system(size: 14, weight: .medium)).foregroundStyle(accent)
                Text("Direct commands and workflows run locally. The optional OpenAI brain uses your API key, stored in macOS Keychain. Recognition requires on-device support unless you enable Apple network recognition above. Recent activity and answers stay in memory; workflows and settings are saved on this Mac.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
                Text("Stop with ⌘. in Newtv1, the menu bar Stop action, or “Newtv1, stop”. Already completed actions cannot be undone automatically. Shell tasks run as your user, time out after 30 seconds, and must be reviewed on screen.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
            }.padding(22).background(surface, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func permissionRow(_ name: String, _ detail: String, _ enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack { VStack(alignment: .leading, spacing: 5) { Text(name).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(muted) }; Spacer(); if enabled { Label("Granted", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(accent) } else { Button("Enable", action: action).buttonStyle(.bordered) } }.padding(20)
    }

    private func title(_ heading: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 9) { Text(heading).font(.system(size: 28, weight: .semibold)).tracking(-0.8); Text(subtitle).font(.system(size: 12)).foregroundStyle(muted) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.accessibility ? accent : Color.orange).frame(width: 5, height: 5)
            Text(model.accessibility ? "Accessibility connected" : "Accessibility permission needed").font(.system(size: 10)).foregroundStyle(muted)
            if !model.accessibility { Button("Set up") { model.page = .settings }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent) }
            Spacer()
            Text("TARGET").font(.system(size: 8, design: .monospaced)).foregroundStyle(muted.opacity(0.7))
            Text(model.targetName).font(.system(size: 10)).foregroundStyle(muted)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 10).padding(.horizontal, 5)
            Text(model.busy ? "Executing…" : speech.status).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
        }.padding(.horizontal, 30).frame(height: 37).background(Color.white.opacity(0.018))
    }

    private func confirmation(_ plan: CommandPlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Review this command", systemImage: "hand.raised").font(.system(size: 23, weight: .semibold))
            if plan.requiresReview { Label("Proposed by your local model", systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(accent) }
            Text("This plan includes an action that needs your approval. All steps are shown below in execution order.").font(.system(size: 12)).foregroundStyle(muted)
            ScrollView { VStack(alignment: .leading, spacing: 14) { ForEach(Array(plan.actions.enumerated()), id: \.offset) { index, action in HStack(alignment: .top) { Text(String(format: "%02d", index + 1)).foregroundStyle(muted); Text(action.summary).textSelection(.enabled); Spacer(); if action.needsConfirmation { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) } }.font(.system(size: 12, design: .monospaced)) } }.padding(18) }.frame(maxHeight: 280).background(surface, in: RoundedRectangle(cornerRadius: 12))
            if plan.actions.contains(where: { if case .shell = $0 { return true }; return false }) { Text("Shell commands have your user’s file and network access. Review the exact code above. Stop can terminate the direct process; detached subprocesses may continue.").font(.system(size: 11)).foregroundStyle(.orange) }
            HStack { Button("Cancel") { model.pending = nil }.keyboardShortcut(.cancelAction); Spacer(); Button("Approve & run") { model.approve() }.buttonStyle(.borderedProminent).foregroundStyle(.black) }
        }.padding(28).frame(width: 570)
    }
}

extension CommandPlan: Identifiable { public var id: String { transcript } }

private let commandGroups: [(String, [String])] = [
    ("Apps & the web", ["open Safari", "switch to Notes", "quit Safari", "go to apple.com", "search for macOS accessibility"]),
    ("Controls & navigation", ["show numbers", "click twelve", "click Save", "hide numbers", "scroll down 5", "scroll right 3"]),
    ("Typing & shortcuts", ["type Hello from Newtv1", "press command shift s", "press return", "copy", "paste", "undo", "new tab", "close tab", "next tab", "go back"]),
    ("Windows", ["left half", "right half", "top half", "bottom half", "maximize window", "center window", "minimize window"]),
    ("Mac & files", ["volume fifty", "mute", "unmute", "take a screenshot", "reveal downloads", "reveal ~/Documents", "lock screen", "sleep my mac"]),
    ("Sequences & power commands", ["open Safari then left half", "run focus mode", "wait 2 seconds", "shell pwd"])
]

private struct VoiceOrb: View {
    let active: Bool
    let level: Float
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active)) { timeline in
            let time = active ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                Circle().fill(Color.purple.opacity(0.09)).frame(width: 172, height: 172).blur(radius: 10)
                Circle().stroke(Color.white.opacity(0.045), lineWidth: 1).frame(width: 167, height: 167)
                ForEach(0..<9) { index in
                    Ellipse().stroke(AngularGradient(colors: [.purple.opacity(0.2), Color(red: 0.55, green: 0.45, blue: 1), .cyan.opacity(0.65), .purple.opacity(0.2)], center: .center), lineWidth: index % 3 == 0 ? 1.5 : 0.7)
                        .frame(width: CGFloat(120 + index * 3), height: CGFloat(74 + index * 6))
                        .rotationEffect(.degrees(Double(index * 23) + sin(time * 0.7 + Double(index)) * 17))
                        .scaleEffect(active ? 1 + Double(level) * 0.11 : 0.96)
                }
                Circle().fill(RadialGradient(colors: [Color(red: 0.55, green: 0.42, blue: 0.95).opacity(0.45), .clear], center: .center, startRadius: 1, endRadius: 65)).frame(width: 125, height: 125)
                Image(systemName: "waveform").font(.system(size: 30, weight: .light)).foregroundStyle(Color.white.opacity(0.8)).shadow(color: .purple, radius: 12)
            }.frame(width: 180, height: 180)
        }
    }
}

private struct WaveMeter: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) { ForEach(0..<12) { index in RoundedRectangle(cornerRadius: 1).fill(accent.opacity(0.7)).frame(width: 2, height: 3 + CGFloat(level) * CGFloat([9, 18, 12, 24, 16, 22, 11, 20, 14, 24, 10, 16][index])) } }.frame(height: 25).animation(.easeOut(duration: 0.12), value: level)
    }
}

private struct WorkflowEditor: View {
    @ObservedObject var model: AppModel
    let workflow: Workflow?
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var commands = ""
    @ViewState private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(workflow == nil ? "Create a workflow" : "Edit workflow").font(.system(size: 25, weight: .semibold))
            Text("Give it a memorable name, then add one command per line.").font(.system(size: 12)).foregroundStyle(muted)
            TextField("e.g. focus mode", text: $name).textFieldStyle(.roundedBorder)
            TextEditor(text: $commands).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden).padding(10).frame(height: 220).background(surface, in: RoundedRectangle(cornerRadius: 10))
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save workflow") { do { try model.saveWorkflow(name: name, commands: commands, replacing: workflow?.id); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).foregroundStyle(.black) }
        }.padding(28).frame(width: 540).onAppear { name = workflow?.name ?? ""; commands = workflow?.commands ?? "open Safari\nleft half\nopen Notes\nright half" }
    }
}

import SwiftUI
import AppKit
import AVFoundation
import Speech
import Newtv1Core

private typealias CompanionState<Value> = SwiftUI.State<Value>

struct CompanionView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    @ObservedObject var speaker: AnswerSpeaker
    @CompanionState private var prompt = ""
    @CompanionState private var guidedConsent = false
    @CompanionState private var correctedTranscript = ""
    @CompanionState private var correctingTranscript = false
    private var tint: Color { WorkspaceTheme.accent }
    private let card = WorkspaceTheme.card

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 20) {
                WorkspaceHeading(title: "A thought away.", subtitle: "Ask a question. Make a plan. Get something done.")
                Spacer()
                NewtSignal(state: model.busy || speech.isTranscribing ? .working : speech.isCapturing ? .listening : .idle, level: speech.level, tint: tint, animated: model.notch.animations)
                    .frame(width: 64, height: 64).accessibilityLabel("Newt status")
            }.padding(.bottom, 6)
            HStack(spacing: 4) {
                ForEach(AssistantMode.allCases) { mode in
                    Button { model.assistantMode = mode } label: {
                        HStack(spacing: 7) { Image(systemName: mode.icon).font(.system(size: 12)); Text(mode.title).font(.system(size: 12, weight: .medium)) }
                            .foregroundStyle(model.assistantMode == mode ? WorkspaceTheme.text : WorkspaceTheme.secondary)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(model.assistantMode == mode ? WorkspaceTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(model.busy || model.capturingScreen)
                        .accessibilityAddTraits(model.assistantMode == mode ? .isSelected : [])
                }
            }.padding(5).background(card, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(model.assistantMode.title, systemImage: model.assistantMode.icon).font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
                    Spacer()
                    Text(model.busy ? "WORKING" : speaker.speaking ? "SPEAKING" : speech.isTranscribing ? "TRANSCRIBING" : speech.isListening ? "LISTENING" : "READY").font(.system(size: 9, design: .monospaced)).foregroundStyle(WorkspaceTheme.secondary)
                }
                Text(model.assistantMode.hint).font(.system(size: 22, weight: .medium, design: .rounded)).tracking(-0.4).padding(.vertical, 6)
                if model.assistantMode == .dictate {
                    Label("Typing into: \(model.targetName)", systemImage: "text.cursor").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
                    Text("Switch to the destination field first. Each pause inserts the recognized text. Say “\(model.wakePhraseLabel), stop dictation” to finish.").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary).lineSpacing(4)
                } else {
                    HStack {
                        TextField(model.assistantMode == .agent ? "Describe a task for your Mac…" : model.assistantMode == .guide ? "What would you like help with on screen?" : "Ask Newt anything…", text: $prompt)
                            .textFieldStyle(.plain).font(.system(size: 14)).onSubmit(send).frame(minHeight: 48)
                        Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.black).frame(width: 36, height: 36).background(tint, in: Circle()) }.buttonStyle(.plain).disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.capturingScreen)
                    }.padding(16).background(WorkspaceTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WorkspaceTheme.line))
                }
                HStack(spacing: 10) {
                    Button { model.toggleListening() } label: { Label(model.speechStarting ? "Cancel microphone startup" : speech.isTranscribing ? "Cancel transcription" : speech.isListening ? "Stop listening" : model.assistantMode == .dictate ? "Start dictation" : "Start listening", systemImage: speech.isListening ? "stop.fill" : "mic.fill") }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black)
                    Text(speech.status != "Microphone off" ? speech.status : model.pushToTalk ? "Hold ⌥ Space · release to send" : model.continuousListening ? "⌥ Space · say \(model.wakePhraseLabel) first" : "⌥ Space · speak, then pause to send").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    if speech.isCapturing { Button("Send now") { speech.finishUtterance() }.buttonStyle(WorkspaceButtonStyle()) }
                    if model.busy || speaker.speaking { Button("Stop") { model.stop(); speech.stop() }.buttonStyle(WorkspaceButtonStyle()).foregroundStyle(.orange) }
                }
                if !speech.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Heard request").font(.system(size: 10, weight: .medium)).foregroundStyle(WorkspaceTheme.secondary)
                        Text(speech.transcript).font(.system(size: 13)).foregroundStyle(tint).textSelection(.enabled)
                        if model.assistantMode != .dictate, !speech.isListening, !model.speechStarting {
                            Button("Correct and retry") {
                                correctedTranscript = speech.transcript
                                correctingTranscript = true
                            }.buttonStyle(WorkspaceButtonStyle()).disabled(model.busy || model.pending != nil || model.capturingScreen)
                        }
                        if correctingTranscript {
                            TextField("Correct your request…", text: $correctedTranscript).textFieldStyle(WorkspaceFieldStyle())
                            HStack {
                                Button("Run corrected request") {
                                    model.retryVoiceTranscript(correctedTranscript)
                                    correctingTranscript = false
                                }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black)
                                    .disabled(correctedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.pending != nil || model.capturingScreen || speech.isListening)
                                Button("Cancel") { correctingTranscript = false }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if model.assistantMode == .talk || model.assistantMode == .guide {
                    HStack {
                        Toggle("Spoken replies", isOn: $model.speakAnswers).toggleStyle(WorkspaceToggleStyle()).controlSize(.mini).font(.system(size: 11)).fixedSize()
                        Spacer()
                        Button("Test Mac voice") { model.speakAnswer("Hi, I'm Newt. I can answer questions, help with your screen, and guide you through your next task.") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(tint)
                    }
                }
            }.padding(26).workspaceCard()
            if !model.busy, speech.transcript.isEmpty, model.assistantMode != .dictate { suggestions }

            if model.assistantMode == .agent {
                DisclosureGroup("Guided control options") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Guided observe / act").font(.system(size: 15, weight: .medium)); Spacer(); Button("Preview controls locally") { model.previewAgentControls() } }
                    Text("For this task, share up to eight observations of the target app’s window title and accessible control labels with \(model.aiProvider.title). Every next action requires review. Field values and screenshots are excluded; visible labels may still contain private text.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                    if !model.guidedObservationPreview.isEmpty { ScrollView { Text(model.guidedObservationPreview).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 100) }
                    Toggle("Allow these observations for my next typed task", isOn: $guidedConsent).font(.system(size: 12)).toggleStyle(WorkspaceToggleStyle())
                }.padding(.top, 14)
                }.padding(20).workspaceCard()
            }

            if model.assistantMode == .guide || model.assistantMode == .talk || model.capturedScreen != nil || model.capturingScreen {
                screenTools
            } else {
                DisclosureGroup("Screen context") { screenTools.padding(.top, 12) }.font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
            }
            if let result = model.lastGuidance {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Screen guidance", systemImage: "viewfinder").font(.system(size: 16, weight: .medium))
                    Text(result.answer).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                    if !result.highlights.isEmpty {
                        ForEach(Array(result.highlights.enumerated()), id: \.offset) { index, highlight in Text("\(index + 1). \(highlight.label)").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary) }
                        HStack { Button("Show highlights for 15 seconds") { model.showLastGuidance() }.buttonStyle(WorkspaceButtonStyle()); Button("Hide highlights") { model.hideGuidance() }.buttonStyle(.plain); Spacer(); Button("Read aloud") { model.speakAnswer(result.answer) }.buttonStyle(.plain) }
                        Text("These marks refer to the captured screen. Capture again if the app or layout has changed. They do not click anything.").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
                    }
                }.padding(22).background(card, in: RoundedRectangle(cornerRadius: 14))
            }
            if let answer = model.brainAnswers.first {
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Text("Latest answer").font(.system(size: 15, weight: .medium)); Spacer(); Button("Read aloud") { model.speakAnswer(answer.markdown) }.buttonStyle(.plain).foregroundStyle(tint); Button("All conversations") { model.openCommandCenter(page: .brain) }.buttonStyle(.plain) }
                    Text((try? AttributedString(markdown: answer.markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(answer.markdown)).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                }.padding(22).background(card, in: RoundedRectangle(cornerRadius: 14))
            }
            if !model.hotkeyAvailable { Text("Option–Space is in use by another app. Quit older Newtv1/Vox copies or use the listening button.").font(.system(size: 12)).foregroundStyle(.orange) }
            HStack {
                Label(model.accessibility ? "Mac control ready" : "Mac control needs setup", systemImage: model.accessibility ? "checkmark.circle" : "hand.raised")
                Spacer()
                Button("Permission setup") { model.openCommandCenter(page: .settings) }.buttonStyle(.plain)
            }.font(.system(size: 11)).foregroundStyle(model.accessibility ? .gray : .orange)
        }.tint(tint)
            .onChange(of: speech.isListening) { listening in
                if listening { correctingTranscript = false }
            }
            .onChange(of: model.assistantMode) { _ in correctingTranscript = false }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A few places to start").font(.system(size: 12, weight: .medium)).foregroundStyle(WorkspaceTheme.secondary)
            HStack(spacing: 10) {
                suggestion("Arrange my workspace", "rectangle.split.2x1", "Open Safari then left half", mode: .command)
                suggestion("Help me understand", "sparkle", "Explain something new to me", mode: .talk)
                suggestion("Plan my next task", "checklist", "Help me plan my next task", mode: .agent)
            }
        }
    }
    private func suggestion(_ title: String, _ icon: String, _ value: String, mode: AssistantMode) -> some View {
        Button { model.assistantMode = mode; prompt = value } label: {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundStyle(tint)
                HStack(alignment: .top) { Text(title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(WorkspaceTheme.secondary) }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).workspaceCard()
        }.buttonStyle(.plain)
    }

    private var screenTools: some View {
        ScreenAccessView(model: model, suggestedQuestion: prompt)
    }

    private func send() {
        guard !model.busy, !model.capturingScreen else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if model.assistantMode == .agent, guidedConsent { model.startGuidedAgent(text); guidedConsent = false }
        else { model.processCompanionInput(text) }
        if model.assistantMode != .guide { prompt = "" }
    }
}

struct AgentJobsView: View {
    @ObservedObject var model: AppModel
    @CompanionState private var search = ""
    @CompanionState private var includeArchived = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 8) { Text("A place for every task.").font(.system(size: 30, weight: .semibold, design: .rounded)); Text("Plans, approvals, steps, and results stay visible while Newt works.").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary) }; Spacer(); Button("New task") { model.assistantMode = .agent; model.openCommandCenter(page: .companion) }.buttonStyle(WorkspaceButtonStyle()) }
            if model.agentJobs.isEmpty { WorkspaceEmptyState(icon: "checklist", title: "Room for your next idea.", detail: "Describe a task to Newt in Agent mode. Its plan, progress, and results will appear here.") }
            HStack { TextField("Search tasks…", text: $search).textFieldStyle(WorkspaceFieldStyle()); Toggle("Include archived", isOn: $includeArchived).toggleStyle(WorkspaceToggleStyle()).fixedSize() }
            ForEach(model.agentJobs.filter { (includeArchived || $0.archived != true) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.goal.localizedCaseInsensitiveContains(search)) }.sorted { ($0.id == model.selectedTaskID ? 0 : 1) < ($1.id == model.selectedTaskID ? 0 : 1) }) { job in
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Label(job.title, systemImage: "sparkles").font(.system(size: 17, weight: .medium)); Spacer(); Text(job.status.rawValue.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundStyle(job.status == .failed ? .orange : model.notch.tint) }
                    Text(job.goal).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
                    ForEach(Array(job.steps.enumerated()), id: \.offset) { index, step in HStack { Text(String(format: "%02d", index + 1)).foregroundStyle(WorkspaceTheme.secondary); Text(step) }.font(.system(size: 11, design: .monospaced)) }
                    Text(job.detail).font(.system(size: 12)).textSelection(.enabled)
                    DisclosureGroup("Conversation & options") { TaskConversationView(model: model, job: job).padding(.top, 12) }
                    Button(job.archived == true ? "Restore task" : "Archive task") { model.archiveTask(job.id, archived: job.archived != true) }.buttonStyle(.plain).font(.system(size: 11)).disabled([.planning, .running, .review].contains(job.status))
                    if job.status == .paused { Button("Mark complete after inspection") { model.markJobComplete(job.id) }.buttonStyle(WorkspaceButtonStyle()) }
                    if !job.trace.isEmpty { DisclosureGroup("Execution observations") { ForEach(Array(job.trace.enumerated()), id: \.offset) { _, line in Text(line).font(.system(size: 10, design: .monospaced)).foregroundStyle(WorkspaceTheme.secondary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) } } }
                    if [.failed, .blocked, .paused].contains(job.status), model.guidedJobID == job.id { Button("Observe and replan next step") { model.replanGuidedAgent() }.buttonStyle(WorkspaceButtonStyle()).disabled(model.busy || model.pending != nil) }
                    if [.failed, .cancelled, .paused].contains(job.status), !job.remaining.isEmpty {
                        Text("Inspect the target app before retrying: the failed action may have partly completed.").font(.system(size: 11)).foregroundStyle(.orange)
                        Button("Review remaining steps") { model.reviewRecovery(job) }.buttonStyle(WorkspaceButtonStyle()).disabled(model.busy || model.pending != nil)
                    }
                    if job.status == .review, model.pending != nil { Button("Review plan") { model.openCommandCenter(page: .control) }.buttonStyle(WorkspaceButtonStyle()) }
                    if job.status == .running || job.status == .planning { Button("Stop task") { model.stop() }.buttonStyle(.plain).foregroundStyle(.orange) }
                }.padding(22).workspaceCard()
            }
        }
    }
}

private struct TaskConversationView: View {
    @ObservedObject var model: AppModel
    let job: AgentJob
    @CompanionState private var reply = ""
    @CompanionState private var shareControls = false
    @CompanionState private var name = ""
    @CompanionState private var schedule = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { TextField("Task name", text: $name).textFieldStyle(WorkspaceFieldStyle()); Button("Rename") { model.renameTask(job.id, name: name) }.buttonStyle(WorkspaceButtonStyle()) }.onAppear { name = job.title }
            if let turns = job.conversation, !turns.isEmpty {
                DisclosureGroup("Task conversation") {
                    ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(turn.role == "user" ? "YOU" : "NEWT").font(.system(size: 9, weight: .semibold)).foregroundStyle(WorkspaceTheme.accent)
                            Text(turn.content).font(.system(size: 12)).textSelection(.enabled)
                        }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            TextField("Follow up on this task…", text: $reply).textFieldStyle(WorkspaceFieldStyle())
            Toggle("Share fresh app control labels with \(model.aiProvider.title) for up to eight more observations", isOn: $shareControls).toggleStyle(WorkspaceToggleStyle()).font(.system(size: 11))
            HStack {
                Button("Send to this task") { model.followUpTask(job.id, text: reply, shareControls: shareControls); reply = ""; shareControls = false }.disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(model.voiceTaskID == job.id ? "Listening for this task…" : "Voice follow-up") { model.dictateTaskFollowUp(job.id) }.disabled(model.busy)
                if shareControls { Button("Continue with fresh controls") { model.continueGuidedTask(job.id); shareControls = false } }
            }.buttonStyle(WorkspaceButtonStyle()).disabled((model.busy && model.guidedJobID != job.id) || model.capturingScreen || model.pending != nil)
            if model.busy, model.guidedJobID == job.id { Text("Follow-ups are applied after the current step. Newt discards a plan generated before your update.").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary) }
            HStack { TextField("Repeat this task, e.g. every Monday at 9 am…", text: $schedule).textFieldStyle(WorkspaceFieldStyle()); Button("Preview routine") { model.scheduleTask(job.id, request: schedule) }.disabled(model.busy || schedule.isEmpty || model.pending != nil) }
            Text("Follow-ups keep this job's goal and recent conversation. Enable local memory in Settings to retain task conversations after restarting.").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
        }
    }
}

struct CompanionPreferences: View {
    @ObservedObject var model: AppModel
    @AppStorage("spokenCaptions") private var spokenCaptions = true
    // Microphone levels redraw the workspace frequently. These system queries
    // can synchronously wait on speech services and must not run on every frame.
    private static let languages = SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted()
    private static let voices = AVSpeechSynthesisVoice.speechVoices().sorted { $0.language == $1.language ? $0.name < $1.name : $0.language < $1.language }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Listening & voice", systemImage: "waveform").font(.system(size: 18, weight: .semibold))
            VoiceCheckView(model: model, speech: model.speech, system: model.automation.system)
            Toggle("Keep listening for more requests", isOn: $model.continuousListening)
            Text("Off captures one request and stops the microphone before running it. Dictate mode continues until you stop it. Continuous listening uses your wake phrase.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
            HStack {
                Text("Pause before sending")
                Slider(value: $model.speechPauseDuration, in: 0.6...3, step: 0.1)
                Text(String(format: "%.1f s", model.speechPauseDuration)).monospacedDigit().frame(width: 45)
            }
            Text("The microphone closes after this much time without speech. Default: 2 seconds. Increase it for longer pauses between phrases.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
            Toggle("Automatic language recognition through \(model.aiProvider.title)", isOn: $model.automaticLanguage).disabled(!model.aiProvider.supportsTranscription)
            if !model.aiProvider.supportsTranscription { Text("ChatGPT account sign-in uses Apple speech recognition. Choose Gemini or OpenAI API to use cloud audio transcription.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary) }
            if model.automaticLanguage { Text("Recorded audio is sent to \(model.aiProvider.title) before the wake phrase is checked. Uses API credits. Turn off to use local Apple recognition.").font(.system(size: 11)).foregroundStyle(.orange) }
            Picker("Mode", selection: $model.assistantMode) { ForEach(AssistantMode.allCases) { Text($0.title).tag($0) } }
            Toggle("Show live captions for spoken replies", isOn: $spokenCaptions)
            Toggle("Hold Option–Space to talk; release to send", isOn: $model.pushToTalk)
            Picker("Recognition language", selection: $model.speechLocale) {
                ForEach(Self.languages, id: \.self) { locale in Text(Locale.current.localizedString(forIdentifier: locale) ?? locale).tag(locale) }
                if !Self.languages.contains(model.speechLocale) { Text(model.speechLocale).tag(model.speechLocale) }
            }
            Text("Apple language support varies. Network recognition is opt-in. Changing language or vocabulary stops listening.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
            Text("Custom vocabulary · one term per line").font(.system(size: 12))
            TextEditor(text: $model.vocabulary).font(.system(size: 12, design: .monospaced)).frame(height: 75).scrollContentBackground(.hidden).padding(8).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            Toggle("Read answers aloud using a Mac voice", isOn: $model.speakAnswers)
            Picker("Voice", selection: $model.voiceID) { Text("System default").tag(""); ForEach(Self.voices, id: \.identifier) { voice in Text("\(voice.name) · \(voice.language)").tag(voice.identifier) } }
            HStack { Text("Speaking speed"); Slider(value: $model.voiceRate, in: 0.3...0.65); Button("Preview voice") { model.speakAnswer("Hi, I'm Newt. What would you like to do?") }.buttonStyle(WorkspaceButtonStyle()) }
            Text("Recognition pauses during playback, then resumes if it was already listening. Press the talk shortcut to interrupt speech. Spoken playback itself stays on this Mac.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
            DisclosureGroup("Response style") {
            Text("How Newt should answer").font(.system(size: 13, weight: .medium))
            TextEditor(text: $model.responsePreferences).font(.system(size: 12)).frame(height: 65)
            Text("For example: “Use simple words, answer briefly, and explain code with examples.” Saved on this Mac and sent with text questions, task planning and browser tasks. Up to 2,000 characters.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
            }
        }.padding(22).workspaceCard().font(.system(size: 12)).toggleStyle(WorkspaceToggleStyle())
    }
}

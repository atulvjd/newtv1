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
    private var tint: Color { model.notch.tint }
    private let card = Color.white.opacity(0.035)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Meet Newt.").font(.system(size: 34, weight: .semibold)).tracking(-1)
                    Text("A voice companion that explains, guides, and gets things done.").font(.system(size: 13)).foregroundStyle(.gray)
                }
                Spacer()
                NewtSignal(state: model.busy ? .working : speech.isListening ? .listening : .idle, level: speech.level, tint: tint, animated: model.notch.animations).frame(width: 70, height: 70)
            }
            HStack(spacing: 8) {
                ForEach(AssistantMode.allCases) { mode in
                    Button { model.assistantMode = mode } label: {
                        VStack(spacing: 9) { Image(systemName: mode.icon).font(.system(size: 17)); Text(mode.title).font(.system(size: 11, weight: .medium)) }
                            .foregroundStyle(model.assistantMode == mode ? tint : .gray).frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(model.assistantMode == mode ? tint.opacity(0.09) : card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.assistantMode == mode ? tint.opacity(0.4) : .clear))
                    }.buttonStyle(.plain).disabled(model.busy || model.capturingScreen)
                }
            }
            if model.assistantMode == .agent {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Guided observe / act").font(.system(size: 15, weight: .medium)); Spacer(); Button("Preview controls locally") { model.previewAgentControls() } }
                    Text("For this task, share up to eight observations of the target app’s window title and accessible control labels with \(model.aiProvider.title). Every next action requires review. Field values and screenshots are excluded; visible labels may still contain private text.").font(.system(size: 11)).foregroundStyle(.gray)
                    if !model.guidedObservationPreview.isEmpty { ScrollView { Text(model.guidedObservationPreview).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 100) }
                    Toggle("Allow these observations for my next typed task", isOn: $guidedConsent).font(.system(size: 12)).toggleStyle(.switch)
                }.padding(18).background(card, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(model.assistantMode.title.uppercased(), systemImage: model.assistantMode.icon).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(tint)
                    Spacer()
                    Text(model.busy ? "WORKING" : speaker.speaking ? "SPEAKING" : speech.isListening ? "LISTENING" : "READY").font(.system(size: 9, design: .monospaced)).foregroundStyle(.gray)
                }
                Text(model.assistantMode.hint).font(.system(size: 16, weight: .medium))
                if model.assistantMode == .dictate {
                    Label("Typing into: \(model.targetName)", systemImage: "text.cursor").font(.system(size: 12)).foregroundStyle(.gray)
                    Text("Switch to the destination field first. Each pause inserts the recognized text. Say “\(model.wakePhraseLabel), stop dictation” to finish.").font(.system(size: 12)).foregroundStyle(.gray).lineSpacing(4)
                } else {
                    HStack {
                        TextField(model.assistantMode == .agent ? "Describe a task for your Mac…" : model.assistantMode == .guide ? "What would you like help with on screen?" : "Ask Newt anything…", text: $prompt)
                            .textFieldStyle(.plain).font(.system(size: 14)).onSubmit(send)
                        Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.black).frame(width: 32, height: 32).background(tint, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.capturingScreen)
                    }.padding(12).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack(spacing: 10) {
                    Button { model.toggleListening() } label: { Label(model.speechStarting ? "Cancel microphone startup" : speech.isListening ? "Stop listening" : model.assistantMode == .dictate ? "Start dictation" : "Start listening", systemImage: speech.isListening ? "stop.fill" : "mic.fill") }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                    Text(speech.status != "Microphone off" ? speech.status : model.pushToTalk ? "Hold ⌥ Space · release to send" : model.continuousListening ? "⌥ Space · say \(model.wakePhraseLabel) first" : "⌥ Space · speak, then pause to send").font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray)
                    Spacer()
                    if speech.isListening { Button("Send now") { speech.finishUtterance() }.buttonStyle(.bordered) }
                    if model.busy || speaker.speaking { Button("Stop") { model.stop(); speech.stop() }.buttonStyle(.bordered).foregroundStyle(.orange) }
                }
                if !speech.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Heard request").font(.system(size: 10, weight: .medium)).foregroundStyle(.gray)
                        Text(speech.transcript).font(.system(size: 13)).foregroundStyle(tint).textSelection(.enabled)
                        if model.assistantMode != .dictate, !speech.isListening, !model.speechStarting {
                            Button("Correct and retry") {
                                correctedTranscript = speech.transcript
                                correctingTranscript = true
                            }.buttonStyle(.bordered).disabled(model.busy || model.pending != nil || model.capturingScreen)
                        }
                        if correctingTranscript {
                            TextField("Correct your request…", text: $correctedTranscript).textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Run corrected request") {
                                    model.retryVoiceTranscript(correctedTranscript)
                                    correctingTranscript = false
                                }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                                    .disabled(correctedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.pending != nil || model.capturingScreen || speech.isListening)
                                Button("Cancel") { correctingTranscript = false }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if model.assistantMode == .talk || model.assistantMode == .guide {
                    HStack {
                        Toggle("Spoken replies", isOn: $model.speakAnswers).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11)).fixedSize()
                        Spacer()
                        Button("Test Mac voice") { model.speakAnswer("Hi, I'm Newt. I can answer questions, help with your screen, and guide you through your next task.") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(tint)
                    }
                }
            }.padding(22).background(card, in: RoundedRectangle(cornerRadius: 15))

            if model.assistantMode == .guide || model.assistantMode == .talk {
                screenTools
            }
            if let result = model.lastGuidance {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Screen guidance", systemImage: "viewfinder").font(.system(size: 16, weight: .medium))
                    Text(result.answer).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                    if !result.highlights.isEmpty {
                        ForEach(Array(result.highlights.enumerated()), id: \.offset) { index, highlight in Text("\(index + 1). \(highlight.label)").font(.system(size: 12)).foregroundStyle(.gray) }
                        HStack { Button("Show highlights for 15 seconds") { model.showLastGuidance() }.buttonStyle(.bordered); Button("Hide highlights") { model.hideGuidance() }.buttonStyle(.plain); Spacer(); Button("Read aloud") { model.speakAnswer(result.answer) }.buttonStyle(.plain) }
                        Text("These marks refer to the captured screen. Capture again if the app or layout has changed. They do not click anything.").font(.system(size: 10)).foregroundStyle(.gray)
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

    private var screenTools: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Screen context", systemImage: "display").font(.system(size: 16, weight: .medium))
                Spacer()
                Text(model.capturedScreen == nil ? "OFF UNTIL REQUESTED" : "LOCAL PREVIEW · NOT SENT").font(.system(size: 8, design: .monospaced)).foregroundStyle(tint)
            }
            Text("Capture is manual. Review the image, then explicitly allow it for one \(model.aiProvider.title) request. Other app windows may contain private information; cancel or close them before sharing.").font(.system(size: 12)).foregroundStyle(.gray).lineSpacing(4)
            HStack {
                Picker("Display", selection: $model.screenDisplayChoice) { Text("Display under pointer").tag("pointer"); ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in Text(screen.localizedName).tag(String(ScreenContext.id(screen))) } }
                Button(model.capturingScreen ? "Preparing…" : "Capture preview") { model.guideQuestion = prompt; model.captureScreenForReview() }.buttonStyle(.bordered).disabled(model.capturingScreen || model.busy)
            }
            if let screen = model.capturedScreen {
                if let image = screen.preview { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 10)) }
                Text("\(screen.displayName) · captured \(screen.capturedAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(.gray)
                TextField("Question about this screen", text: $model.guideQuestion).textFieldStyle(.roundedBorder)
                HStack {
                    if model.approvedScreenID == screen.id { Label("Approved for one request", systemImage: "checkmark.shield").font(.system(size: 11)).foregroundStyle(tint) }
                    else { Button("Use this screen") { model.approvedScreenID = screen.id }.buttonStyle(.bordered) }
                    Spacer()
                    Button("Read text locally") { model.readScreenLocally() }.buttonStyle(.plain).disabled(model.capturingScreen)
                    Button("Discard") { model.clearScreenContext() }.buttonStyle(.plain)
                    Button("Ask about screen") { model.askUsingApprovedScreen() }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(model.approvedScreenID != screen.id || model.busy || model.capturingScreen)
                }
                if !model.localScreenText.isEmpty { Text(model.localScreenText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).lineLimit(16) }
            }
        }.padding(22).background(card, in: RoundedRectangle(cornerRadius: 15))
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
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 8) { Text("Your tasks, in view.").font(.system(size: 29, weight: .semibold)); Text("Plans, approvals, steps, and results stay visible while Newt works.").font(.system(size: 12)).foregroundStyle(.gray) }; Spacer(); Button("New task") { model.assistantMode = .agent; model.openCommandCenter(page: .companion) }.buttonStyle(.bordered) }
            if model.agentJobs.isEmpty { Text("Choose Agent in Companion, describe a Mac task, then review the plan. Tasks are serialized. Enable local memory to retain task history across launches.").font(.system(size: 13)).foregroundStyle(.gray).lineSpacing(5) }
            ForEach(model.agentJobs) { job in
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Label(job.title, systemImage: "sparkles").font(.system(size: 17, weight: .medium)); Spacer(); Text(job.status.rawValue.uppercased()).font(.system(size: 9, design: .monospaced)).foregroundStyle(job.status == .failed ? .orange : model.notch.tint) }
                    Text(job.goal).font(.system(size: 12)).foregroundStyle(.gray)
                    ForEach(Array(job.steps.enumerated()), id: \.offset) { index, step in HStack { Text(String(format: "%02d", index + 1)).foregroundStyle(.gray); Text(step) }.font(.system(size: 11, design: .monospaced)) }
                    Text(job.detail).font(.system(size: 12)).textSelection(.enabled)
                    if job.status == .paused { Button("Mark complete after inspection") { model.markJobComplete(job.id) }.buttonStyle(.bordered) }
                    if !job.trace.isEmpty { DisclosureGroup("Execution observations") { ForEach(Array(job.trace.enumerated()), id: \.offset) { _, line in Text(line).font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) } } }
                    if [.failed, .blocked, .paused].contains(job.status), model.guidedJobID == job.id { Button("Observe and replan next step") { model.replanGuidedAgent() }.buttonStyle(.bordered).disabled(model.busy || model.pending != nil) }
                    if [.failed, .cancelled].contains(job.status), !job.remaining.isEmpty {
                        Text("Inspect the target app before retrying: the failed action may have partly completed.").font(.system(size: 11)).foregroundStyle(.orange)
                        Button("Review remaining steps") { model.reviewRecovery(job) }.buttonStyle(.bordered).disabled(model.busy || model.pending != nil)
                    }
                    if job.status == .review, model.pending != nil { Button("Review plan") { model.openCommandCenter(page: .control) }.buttonStyle(.bordered) }
                    if job.status == .running || job.status == .planning { Button("Stop task") { model.stop() }.buttonStyle(.plain).foregroundStyle(.orange) }
                }.padding(22).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct CompanionPreferences: View {
    @ObservedObject var model: AppModel
    @AppStorage("spokenCaptions") private var spokenCaptions = true
    private var languages: [String] { SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted() }
    private var voices: [AVSpeechSynthesisVoice] { AVSpeechSynthesisVoice.speechVoices().sorted { $0.language == $1.language ? $0.name < $1.name : $0.language < $1.language } }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Companion & voice", systemImage: "bubble.left.and.bubble.right").font(.system(size: 17, weight: .medium))
            Toggle("Keep listening for more requests", isOn: $model.continuousListening)
            Text("With this off, Newt captures one request, stops the microphone after you finish, and runs it. Dictate mode continues until you stop it. Press Start listening or Option–Space and speak directly. Continuous listening uses your wake-phrase setting.").font(.system(size: 11)).foregroundStyle(.gray)
            HStack {
                Text("Pause before sending")
                Slider(value: $model.speechPauseDuration, in: 0.6...3, step: 0.1)
                Text(String(format: "%.1f s", model.speechPauseDuration)).monospacedDigit().frame(width: 45)
            }
            Text("Newt waits for quiet audio and a stable transcript. Increase this pause if you think between phrases.").font(.system(size: 11)).foregroundStyle(.gray)
            Toggle("Automatic language recognition through \(model.aiProvider.title)", isOn: $model.automaticLanguage)
            if model.automaticLanguage { Text("While listening, speech segments are sent to \(model.aiProvider.title) before the wake phrase is checked. API charges apply. Hold-to-talk limits capture to each key press; continuous listening uses silence detection. Recognition pauses while each segment uploads. Turn this off for local Apple recognition.").font(.system(size: 11)).foregroundStyle(.orange) }
            Picker("Mode", selection: $model.assistantMode) { ForEach(AssistantMode.allCases) { Text($0.title).tag($0) } }
            Toggle("Show live captions for spoken replies", isOn: $spokenCaptions)
            Toggle("Hold Option–Space to talk; release to send", isOn: $model.pushToTalk)
            Picker("Recognition language", selection: $model.speechLocale) {
                ForEach(languages, id: \.self) { locale in Text(Locale.current.localizedString(forIdentifier: locale) ?? locale).tag(locale) }
                if !languages.contains(model.speechLocale) { Text(model.speechLocale).tag(model.speechLocale) }
            }
            Text("Available languages depend on Apple's recognizer. On-device support varies; network recognition stays opt-in. Changing language or vocabulary stops listening.").font(.system(size: 11)).foregroundStyle(.gray)
            Text("Custom vocabulary · one term per line").font(.system(size: 12))
            TextEditor(text: $model.vocabulary).font(.system(size: 12, design: .monospaced)).frame(height: 75).scrollContentBackground(.hidden).padding(8).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            Toggle("Read answers aloud using a Mac voice", isOn: $model.speakAnswers)
            Picker("Voice", selection: $model.voiceID) { Text("System default").tag(""); ForEach(voices, id: \.identifier) { voice in Text("\(voice.name) · \(voice.language)").tag(voice.identifier) } }
            HStack { Text("Speaking speed"); Slider(value: $model.voiceRate, in: 0.3...0.65); Button("Preview voice") { model.speakAnswer("Hi, I'm Newt. What would you like to do?") }.buttonStyle(.bordered) }
            Text("Recognition pauses during playback, then resumes if it was already listening. Press the talk shortcut to interrupt speech. Spoken playback itself stays on this Mac.").font(.system(size: 11)).foregroundStyle(.gray)
            Divider()
            Toggle("Remember conversations on this Mac", isOn: $model.rememberConversations)
            Text("Off by default. When enabled, up to 30 text answers are saved in Application Support; screenshots are never saved there. Turning this off stops saving and loading, but use Clear history to remove previously saved text. Recent conversation text is sent as context when you ask follow-ups.").font(.system(size: 11)).foregroundStyle(.gray).lineSpacing(3)
            Button("Clear conversation history…") { model.clearConversationHistory() }.buttonStyle(.bordered)
        }.padding(22).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14)).font(.system(size: 12)).toggleStyle(.switch)
    }
}

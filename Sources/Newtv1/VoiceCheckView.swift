import SwiftUI

struct VoiceCheckView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    @ObservedObject var system: SystemControls

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Voice check", systemImage: "mic.badge.waveform").font(.system(size: 14, weight: .medium))
            Text("Say a sentence, then stay quiet for two seconds. This check displays your words without running a command.")
                .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
            Text("Input: " + (system.inputs.first(where: { $0.id == system.inputID })?.name ?? "No microphone found"))
            if system.microphoneMuted {
                Text("Your system microphone is muted or its input volume is zero. Restore it in System Controls before testing.").foregroundStyle(.orange)
            }
            HStack {
                Button(model.testingSpeech && speech.isListening ? "Cancel voice check" : "Start voice check") {
                    if model.testingSpeech && speech.isListening { model.stopSpeechTest() }
                    else { model.testSpeech() }
                }.buttonStyle(WorkspaceButtonStyle())
                    .disabled(model.busy || model.pending != nil || model.capturingScreen || model.speechStarting || speech.checkingEngine || (speech.isListening && !model.testingSpeech))
                Button(speech.checkingEngine ? "Checking engine…" : "Check recognition engine") {
                    speech.checkRecognitionEngine(locale: model.speechLocale)
                }.buttonStyle(WorkspaceButtonStyle()).disabled(speech.isListening || model.speechStarting || speech.checkingEngine)
                if model.testingSpeech && speech.isCapturing {
                    ProgressView(value: Double(speech.level)).frame(width: 100).accessibilityLabel("Microphone input level")
                }
            }
            if model.testingSpeech || !model.voiceTestTranscript.isEmpty {
                Text(speech.status).foregroundStyle(WorkspaceTheme.secondary)
                Text(model.voiceTestTranscript.isEmpty ? speech.transcript : model.voiceTestTranscript)
                    .foregroundStyle(WorkspaceTheme.accent).textSelection(.enabled)
            }
            if !speech.engineCheckResult.isEmpty {
                Text(speech.engineCheckResult).foregroundStyle(WorkspaceTheme.secondary).textSelection(.enabled)
            }
        }.font(.system(size: 12)).padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .onAppear { system.refresh() }
            .onDisappear { model.stopSpeechTest() }
    }
}

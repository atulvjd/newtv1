import AppKit
import Speech
import AVFoundation

@MainActor
final class SpeechController: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var level: Float = 0
    @Published var status = "Microphone off"
    var onUtterance: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var wakePhrases = ["Newt", "New", "Hey Newt", "Hey New"]
    var localeIdentifier = "en-US"
    var vocabulary: [String] = []
    var dictation = false
    var automaticLanguage = false
    var transcribeAudio: ((Data) async throws -> String)?
    private let cloud = CloudSpeechRecorder()
    var submitsOnPause = true
    private let engine = AVAudioEngine()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var tapInstalled = false
    private var startToken = UUID()
    private var generation = UUID()
    private var consumed = false
    private var lastText = ""
    private var sessionStarted = Date()
    private var finishing = false
    private var finalTimeout: Task<Void, Never>?
    private var currentAllowNetwork = false

    func start(allowNetwork: Bool) async {
        guard !isListening else { return }
        let startToken = UUID(); self.startToken = startToken
        if automaticLanguage {
            guard let transcribeAudio else { fail("Configure the OpenAI key before using automatic language recognition."); return }
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            guard self.startToken == startToken, !Task.isCancelled else { return }
            guard microphone else { fail("Allow Microphone for Newtv1 in Privacy & Security."); return }
            cloud.transcribe = transcribeAudio
            cloud.onText = { [weak self] text in guard let self, self.isListening else { return }; self.transcript = text; self.onUtterance?(text) }
            cloud.onLevel = { [weak self] level in self?.level = level }
            cloud.onFailure = { [weak self] message in self?.fail(message) }
            cloud.onFinished = { [weak self] in self?.isListening = false; self?.status = "Microphone off" }
            do { try cloud.start(hold: !submitsOnPause); isListening = true; transcript = ""; status = "Automatic language · audio sent to OpenAI" }
            catch { fail(error.localizedDescription) }
            return
        }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        currentAllowNetwork = allowNetwork
        status = "Checking permissions…"
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard self.startToken == startToken, !Task.isCancelled else { return }
        guard speech == .authorized else { fail("Allow Speech Recognition for Newtv1 in System Settings → Privacy & Security."); return }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard self.startToken == startToken, !Task.isCancelled else { return }
        guard microphone else { fail("Allow Microphone for Newtv1 in System Settings → Privacy & Security."); return }
        guard let recognizer, recognizer.isAvailable else { fail("Speech recognition for the selected language is unavailable on this Mac right now."); return }
        guard recognizer.supportsOnDeviceRecognition || allowNetwork else {
            fail("On-device recognition for this language is unavailable. Choose another language or opt into Apple network recognition in Settings."); return
        }
        isListening = true
        beginSession(allowNetwork: allowNetwork)
    }

    private func beginSession(allowNetwork: Bool) {
        guard isListening, let recognizer else { return }
        tearDownSession()
        let token = UUID(); generation = token
        consumed = false; finishing = false; lastText = ""; transcript = ""; sessionStarted = Date()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = dictation
        request.requiresOnDeviceRecognition = !allowNetwork
        request.taskHint = .dictation
        request.contextualStrings = Array((wakePhrases + vocabulary + ["show numbers", "left half", "right half", "run focus mode"]).prefix(100))
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("No working microphone found."); return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += channel[index] * channel[index] }
            let level = min(1, sqrt(sum / Float(count)) * 8)
            Task { @MainActor [weak self] in self?.level = level }
        }
        tapInstalled = true
        do { engine.prepare(); try engine.start() }
        catch { fail("Microphone could not start: \(error.localizedDescription)"); return }
        status = request.requiresOnDeviceRecognition ? "On-device recognition" : "Apple network recognition allowed"
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, self.generation == token else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    if text != self.lastText {
                        self.lastText = text
                        self.silenceTask?.cancel()
                        if self.submitsOnPause { self.silenceTask = Task { [weak self] in
                            do { try await Task.sleep(nanoseconds: 1_100_000_000) } catch { return }
                            self?.consume(text, allowNetwork: allowNetwork)
                        } }
                    }
                    if result.isFinal, self.submitsOnPause || self.finishing { self.consume(text, allowNetwork: allowNetwork) }
                }
                if let error, !self.consumed {
                    if self.finishing {
                        if self.lastText.isEmpty { self.stop() }
                        else { self.consume(self.lastText, allowNetwork: allowNetwork) }
                        return
                    }
                    // Speech sessions expire. Restart with backoff; permission/service errors stop visibly.
                    if Date().timeIntervalSince(self.sessionStarted) < 2 {
                        self.fail("Speech recognition stopped: \(error.localizedDescription)")
                    } else { self.scheduleRestart(allowNetwork: allowNetwork, delay: 800_000_000) }
                }
            }
        }
        rotationTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 50_000_000_000) } catch { return }
            self?.beginSession(allowNetwork: allowNetwork)
        }
    }

    private func consume(_ text: String, allowNetwork: Bool) {
        guard isListening, !consumed, !text.isEmpty else { return }
        consumed = true
        silenceTask?.cancel()
        if finishing { stop() }
        onUtterance?(text)
        // Start with an empty transcript so recognition never replays an earlier action.
        if isListening { scheduleRestart(allowNetwork: allowNetwork, delay: 250_000_000) }
    }

    private func scheduleRestart(allowNetwork: Bool, delay: UInt64) {
        tearDownSession()
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            self?.beginSession(allowNetwork: allowNetwork)
        }
    }

    func stop() {
        startToken = UUID()
        cloud.stop()
        isListening = false; restartTask?.cancel(); restartTask = nil
        tearDownSession(); level = 0; status = "Microphone off"
        finalTimeout?.cancel(); finalTimeout = nil; finishing = false
    }

    func finishUtterance() {
        guard isListening else { return }
        if automaticLanguage { cloud.finish(); return }
        finishing = true; silenceTask?.cancel(); rotationTask?.cancel(); restartTask?.cancel()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        finalTimeout?.cancel()
        finalTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
            guard let self, self.isListening else { return }
            if self.lastText.isEmpty { self.stop() }
            else { self.consume(self.lastText, allowNetwork: self.currentAllowNetwork) }
        }
    }

    private func tearDownSession() {
        generation = UUID()
        silenceTask?.cancel(); rotationTask?.cancel()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); recognitionTask?.cancel()
        recognitionTask = nil; request = nil
    }

    private func fail(_ message: String) { stop(); status = message; onFailure?(message) }
}

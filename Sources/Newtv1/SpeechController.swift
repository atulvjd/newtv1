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
    private let engine = AVAudioEngine()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var tapInstalled = false
    private var generation = UUID()
    private var consumed = false
    private var lastText = ""
    private var sessionStarted = Date()

    func start(allowNetwork: Bool) async {
        guard !isListening else { return }
        status = "Checking permissions…"
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { fail("Allow Speech Recognition for Newtv1 in System Settings → Privacy & Security."); return }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphone else { fail("Allow Microphone for Newtv1 in System Settings → Privacy & Security."); return }
        guard let recognizer, recognizer.isAvailable else { fail("English speech recognition is unavailable on this Mac right now."); return }
        guard recognizer.supportsOnDeviceRecognition || allowNetwork else {
            fail("On-device English speech recognition is unavailable. You can opt into Apple network recognition in Settings."); return
        }
        isListening = true
        beginSession(allowNetwork: allowNetwork)
    }

    private func beginSession(allowNetwork: Bool) {
        guard isListening, let recognizer else { return }
        tearDownSession()
        let token = UUID(); generation = token
        consumed = false; lastText = ""; transcript = ""; sessionStarted = Date()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.requiresOnDeviceRecognition = !allowNetwork
        request.taskHint = .dictation
        request.contextualStrings = ["Newtv1", "New TV One", "Hey New TV One", "show numbers", "left half", "right half", "run focus mode"]
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
                        self.silenceTask = Task { [weak self] in
                            do { try await Task.sleep(nanoseconds: 1_100_000_000) } catch { return }
                            self?.consume(text, allowNetwork: allowNetwork)
                        }
                    }
                    if result.isFinal { self.consume(text, allowNetwork: allowNetwork) }
                }
                if let error, !self.consumed {
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
        isListening = false; restartTask?.cancel(); restartTask = nil
        tearDownSession(); level = 0; status = "Microphone off"
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

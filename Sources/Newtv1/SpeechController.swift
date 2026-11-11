import AppKit
import Speech
import AVFoundation
import Newtv1Core

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
    var submitsOnPause = true
    var continuousListening = false
    var silenceDuration: TimeInterval = 1.4
    private let cloud = CloudSpeechRecorder()
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var monitor: Timer?
    private var restartTask: Task<Void, Never>?
    private var finalTimeout: Task<Void, Never>?
    private var endpoint = SpeechEndpoint(now: ProcessInfo.processInfo.systemUptime)
    private var tapInstalled = false
    private var startToken = UUID()
    private var generation = UUID()
    private var segmentStarted = 0.0
    private var lastAudioSample = 0.0
    private var committedText = ""
    private var segmentText = ""
    private var finishing = false
    private var rotating = false
    private var delivered = false
    private var allowNetwork = false
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(allowNetwork: Bool) async {
        guard !isListening else { return }
        let token = UUID()
        startToken = token
        status = "Checking microphone…"
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard startToken == token, !Task.isCancelled else { return }
        guard microphone else { fail("Allow Microphone for Newtv1 in Privacy & Security."); return }
        transcript = ""
        delivered = false
        self.allowNetwork = allowNetwork
        if automaticLanguage {
            guard let transcribeAudio else { fail("Configure the AI provider key before using automatic language recognition."); return }
            cloud.transcribe = transcribeAudio
            cloud.silenceDuration = silenceDuration
            cloud.continuousListening = continuousListening
            cloud.onText = { [weak self] text in self?.deliver(text) }
            cloud.onLevel = { [weak self] value in self?.level = value }
            cloud.onStatus = { [weak self] message in self?.status = message }
            cloud.onFailure = { [weak self] message in self?.fail(message) }
            cloud.onFinished = { [weak self] in self?.stop() }
            do {
                isListening = true
                try cloud.start(hold: !submitsOnPause)
            } catch { fail(error.localizedDescription) }
            return
        }
        status = "Checking speech recognition…"
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard startToken == token, !Task.isCancelled else { return }
        guard authorization == .authorized else { fail("Allow Speech Recognition for Newtv1 in Privacy & Security."); return }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard let recognizer, recognizer.isAvailable else { fail("The selected speech language is unavailable on this Mac."); return }
        guard recognizer.supportsOnDeviceRecognition || allowNetwork else {
            fail("On-device recognition for this language is unavailable. Choose another language or enable Apple network recognition in Settings.")
            return
        }
        isListening = true
        resetUtterance()
        beginSegment()
        monitor = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func resetUtterance() {
        endpoint = SpeechEndpoint(silenceDuration: silenceDuration, now: now)
        committedText = ""
        segmentText = ""
        transcript = ""
        delivered = false
        finishing = false
        rotating = false
    }

    private func beginSegment() {
        guard isListening, let recognizer else { return }
        tearDownSegment()
        let token = UUID()
        generation = token
        segmentStarted = now
        lastAudioSample = now
        segmentText = ""
        rotating = false
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = dictation
        request.requiresOnDeviceRecognition = !allowNetwork
        request.taskHint = .dictation
        request.contextualStrings = Array((wakePhrases + vocabulary + ["show numbers", "left half", "right half", "run focus mode"]).prefix(100))
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { fail("No working microphone found. Check your input device in Sound settings."); return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
            let rms = sqrt(sum / Float(buffer.frameLength))
            let power = Double(20 * log10(max(rms, 0.00001)))
            let timestamp = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, self.isListening, self.generation == token, !self.finishing else { return }
                self.lastAudioSample = timestamp
                self.level = min(1, rms * 8)
                self.endpoint.observe(powerDB: power, now: timestamp)
            }
        }
        tapInstalled = true
        do { engine.prepare(); try engine.start() }
        catch { fail("Microphone could not start. Check the selected input device and try again."); return }
        status = "Listening · finish speaking to send"
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, self.generation == token else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty, text != self.segmentText {
                        self.segmentText = text
                        self.transcript = self.joinedText
                        if !text.isEmpty { self.endpoint.transcriptChanged(now: self.now) }
                    }
                    if result.isFinal {
                        if self.finishing { self.completeUtterance() }
                        else { self.commitAndContinue() }
                        return
                    }
                }
                if error != nil {
                    if self.finishing || self.rotating { self.fail("Speech recognition ended before finalizing your words. Your partial request is on screen. Try again.") }
                    else { self.fail("Speech recognition was interrupted. Your partial request was kept on screen. Check your microphone and try again.") }
                }
            }
        }
    }

    private var joinedText: String {
        [committedText, segmentText].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func tick() {
        guard isListening, !finishing, !rotating else { return }
        guard now - lastAudioSample < 3 else {
            fail("The microphone stopped delivering audio. Check your input device and try again.")
            return
        }
        switch endpoint.state(now: now) {
        case .idleTimeout:
            stop()
            status = "No speech heard · press Start listening to try again"
        case .durationLimit:
            fail("This request reached the three-minute recording limit. Your partial transcript is on screen. Try a shorter request.")
        case .finished where submitsOnPause:
            finishUtterance()
        case .speaking:
            status = "Hearing you…"
        case .pausing:
            status = "Waiting for you to finish…"
        default:
            break
        }
        if isListening, !finishing, now - segmentStarted >= 50 {
            rotating = true
            endAudio()
            awaitFinalResult()
        }
    }

    private func commitAndContinue() {
        rotating = true
        committedText = joinedText
        segmentText = ""
        tearDownSegment()
        restartTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            guard let self, self.isListening, !self.finishing else { return }
            self.beginSegment()
        }
    }

    func finishUtterance() {
        guard isListening else { return }
        if automaticLanguage { cloud.finish(); return }
        guard !finishing else { return }
        finishing = true
        rotating = false
        restartTask?.cancel()
        status = "Finishing transcription…"
        endAudio()
        awaitFinalResult()
    }

    private func endAudio() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        level = 0
        request?.endAudio()
    }

    private func awaitFinalResult() {
        finalTimeout?.cancel()
        let token = generation
        finalTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: self?.allowNetwork == true ? 8_000_000_000 : 3_000_000_000) } catch { return }
            guard let self, self.isListening, self.generation == token else { return }
            self.fail("Speech recognition took too long to finalize. Your partial request is on screen. Check your recognition language and try again.")
        }
    }

    private func completeUtterance() {
        let text = joinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            stop()
            status = "No words recognized · check your input device and recognition language"
            return
        }
        deliver(text)
    }

    private func deliver(_ text: String) {
        guard isListening, !delivered else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        delivered = true
        transcript = text
        let continueAfter = continuousListening && submitsOnPause
        if !continueAfter {
            stop()
            status = "Request captured"
        } else if !automaticLanguage {
            tearDownSegment()
        }
        onUtterance?(text)
        if continueAfter, isListening {
            if automaticLanguage { delivered = false }
            else { resetUtterance(); beginSegment() }
        }
    }

    func stop() {
        startToken = UUID()
        isListening = false
        cloud.stop()
        monitor?.invalidate()
        monitor = nil
        tearDownSegment()
        finishing = false
        rotating = false
        level = 0
        status = "Microphone off"
    }

    private func tearDownSegment() {
        generation = UUID()
        restartTask?.cancel()
        restartTask = nil
        finalTimeout?.cancel()
        finalTimeout = nil
        endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
    }

    private func fail(_ message: String) {
        stop()
        status = message
        onFailure?(message)
    }
}

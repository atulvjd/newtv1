import AppKit
import Speech
import AVFoundation
import Newtv1Core

@MainActor
final class SpeechController: ObservableObject {
    @Published var isListening = false
    @Published private(set) var isTranscribing = false
    var isCapturing: Bool { isListening && !isTranscribing }
    @Published var transcript = ""
    @Published var level: Float = 0
    @Published var status = "Microphone off"
    @Published private(set) var checkingEngine = false
    @Published private(set) var engineCheckResult = ""
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
    var silenceDuration: TimeInterval = 2
    private let cloud = CloudSpeechRecorder()
    private let capture = SpeechAudioCapture()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var monitor: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var finalTimeout: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var engineCheckTask: Task<Void, Never>?
    private var recordings: [URL] = []
    private var audioStarted: TimeInterval?
    private var endpoint = SpeechEndpoint(now: ProcessInfo.processInfo.systemUptime)
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

    func checkRecognitionEngine(locale: String) {
        guard !isListening, !checkingEngine else { return }
        checkingEngine = true
        engineCheckResult = "Checking Apple's offline recognizer with generated audio…"
        engineCheckTask = Task { [weak self] in
            guard let self else { return }
            defer { self.checkingEngine = false; self.engineCheckTask = nil }
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard !Task.isCancelled else { return }
            guard authorization == .authorized else {
                self.engineCheckResult = "Speech Recognition permission is needed for this Newtv1 copy."
                return
            }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
                  recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                self.engineCheckResult = "On-device recognition is unavailable for this language. Choose an installed recognition language."
                return
            }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("newtv1-speech-check-\(UUID().uuidString).aiff")
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                _ = try await ProcessRunner().run("/usr/bin/say", ["-r", "160", "-o", file.path, "Newt, open Calculator."])
                try Task.checkCancellation()
                let text = try await SpeechFileTranscriber().transcribe(file, recognizer: recognizer,
                    allowNetwork: false, vocabulary: wakePhrases + ["Calculator"], dictation: false)
                try Task.checkCancellation()
                self.engineCheckResult = "Apple offline recognition returned: “\(text)”. Use Voice check to test your microphone next."
            } catch {
                if !Task.isCancelled { self.engineCheckResult = self.recognitionError(error) }
            }
        }
    }

    func start(allowNetwork: Bool) async {
        guard !isListening, !checkingEngine else { return }
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
            cloud.onStatus = { [weak self] message in self?.setStatus(message) }
            cloud.onFailure = { [weak self] message in self?.fail(message) }
            cloud.onTranscribing = { [weak self] active in self?.isTranscribing = active }
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
        guard isListening else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard let self, self.isListening else { return }
                self.tick()
            }
        }
    }

    private func resetUtterance() {
        removeRecordings()
        endpoint = SpeechEndpoint(silenceDuration: silenceDuration, now: now, usesSpeechClassification: true)
        isTranscribing = false
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
        audioStarted = nil
        segmentText = ""
        rotating = false
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = dictation
        request.requiresOnDeviceRecognition = !allowNetwork
        request.taskHint = .dictation
        request.contextualStrings = Array((wakePhrases + vocabulary + ["show numbers", "left half", "right half", "run focus mode"]).prefix(100))
        self.request = request
        // Attach the recognizer before the microphone starts delivering buffers.
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, self.generation == token else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if let start = self.audioStarted, let last = result.bestTranscription.segments.last,
                       last.duration > 0 {
                        self.endpoint.recognizedSpeech(through: start + last.timestamp + last.duration)
                    }
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
                if let error {
                    if self.finishing { self.recoverFinalResult() }
                    else { self.fail(self.recognitionError(error)) }
                }
            }
        }
        do {
            try capture.start(recording: true, onBuffer: { buffer in request.append(buffer) },
                onSample: { [weak self] power, rms, timestamp in
                    Task { @MainActor [weak self] in
                        guard let self, self.isCapturing, self.generation == token, !self.rotating else { return }
                        if self.audioStarted == nil { self.audioStarted = timestamp }
                        self.lastAudioSample = timestamp
                        let level = min(1, rms * 8)
                        if abs(self.level - level) >= 0.025 || (level == 0 && self.level != 0) { self.level = level }
                        self.endpoint.observe(powerDB: power, now: timestamp)
                    }
                }, onSpeech: { [weak self] probability, timestamp in
                    Task { @MainActor [weak self] in
                        guard let self, self.isCapturing, self.generation == token, !self.rotating else { return }
                        self.endpoint.observeSpeech(probability: probability, through: timestamp)
                    }
                }, onFailure: { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.isListening, self.generation == token else { return }
                        self.fail(message)
                    }
                })
        } catch { fail("Microphone or voice detection could not start: " + error.localizedDescription); return }
        status = "Listening · pause for \(String(format: "%.1f", silenceDuration)) seconds to send"
    }

    private var joinedText: String {
        [committedText, segmentText].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func tick() {
        guard isListening, !finishing, !rotating else { return }
        switch endpoint.state(now: now) {
        case .idleTimeout:
            stop()
            status = "No speech heard · press Start listening to try again"
        case .durationLimit:
            fail("This request reached the three-minute recording limit. Your partial transcript is on screen. Try a shorter request.")
        case .finished where submitsOnPause:
            finishUtterance()
        case .speaking:
            setStatus("Hearing you…")
        case .pausing:
            setStatus("Waiting for you to finish…")
        default:
            break
        }
        if isCapturing, now - lastAudioSample >= 2 {
            fail("The microphone stopped delivering audio. Check your input device and try again.")
            return
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
        isTranscribing = true
        status = "Microphone off · finishing transcription…"
        // A final result can arrive just before Send now, between recognition
        // segments. Its task has already been torn down and cannot finalize again.
        if request == nil, !committedText.isEmpty { completeUtterance(); return }
        endAudio()
        awaitFinalResult()
    }

    private func endAudio() {
        recordings.append(contentsOf: capture.finish())
        level = 0
        request?.endAudio()
    }

    private func awaitFinalResult() {
        finalTimeout?.cancel()
        let token = generation
        finalTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: self?.allowNetwork == true ? 8_000_000_000 : 3_000_000_000) } catch { return }
            guard let self, self.isListening, self.generation == token else { return }
            if self.finishing { self.recoverFinalResult() }
            else { self.fail("Apple speech recognition stopped during a long request. Your partial transcript is on screen; try a shorter request.") }
        }
    }

    private func recoverFinalResult() {
        guard recoveryTask == nil, let recognizer, !recordings.isEmpty else {
            if recoveryTask == nil { fail("No audio was available to finish transcription. Check your microphone input in Settings → Voice.") }
            return
        }
        generation = UUID()
        finalTimeout?.cancel(); finalTimeout = nil
        recognitionTask?.cancel(); recognitionTask = nil
        request = nil
        status = allowNetwork ? "Microphone off · recovering transcription…" : "Microphone off · recovering transcription locally…"
        let token = generation, files = recordings
        let allowNetwork = allowNetwork, vocabulary = wakePhrases + vocabulary, dictation = dictation
        recoveryTask = Task { [weak self] in
            do {
                var parts: [String] = []
                for file in files {
                    try Task.checkCancellation()
                    let text = try await SpeechFileTranscriber().transcribe(file, recognizer: recognizer,
                        allowNetwork: allowNetwork, vocabulary: vocabulary, dictation: dictation)
                    parts.append(text)
                }
                guard let self, self.isListening, self.generation == token, !Task.isCancelled else { return }
                self.recoveryTask = nil
                self.deliver(parts.joined(separator: " "))
            } catch {
                guard let self, self.isListening, self.generation == token, !Task.isCancelled else { return }
                self.recoveryTask = nil
                self.fail(self.recognitionError(error))
            }
        }
    }

    private func recognitionError(_ error: Error) -> String {
        let detail = error as NSError
        return "Apple speech recognition: \(detail.localizedDescription) (\(detail.domain) \(detail.code)). Your partial transcript is on screen. Check the input and recognition language in Settings → Voice."
    }

    private func removeRecordings() {
        for file in recordings { try? FileManager.default.removeItem(at: file) }
        recordings.removeAll()
    }

    private func setStatus(_ message: String) {
        if status != message { status = message }
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
        isTranscribing = false
        cloud.stop()
        monitor?.cancel()
        monitor = nil
        tearDownSegment()
        recoveryTask?.cancel(); recoveryTask = nil
        engineCheckTask?.cancel(); engineCheckTask = nil
        checkingEngine = false
        removeRecordings()
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

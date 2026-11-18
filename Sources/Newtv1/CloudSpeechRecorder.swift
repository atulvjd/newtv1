import AppKit
import AVFoundation
import Newtv1Core

@MainActor
final class CloudSpeechRecorder {
    var onText: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onStatus: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var onFinished: (() -> Void)?
    var transcribe: ((Data) async throws -> String)?
    var onTranscribing: ((Bool) -> Void)?
    var silenceDuration: TimeInterval = 2
    var continuousListening = false
    private let capture = SpeechAudioCapture()
    private var recording = false
    private var lastAudioSample = 0.0
    private var timer: Task<Void, Never>?
    private var segments: [URL] = []
    private var endpoint = SpeechEndpoint(now: ProcessInfo.processInfo.systemUptime)
    private var running = false
    private var hold = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(hold: Bool) throws {
        stop()
        self.hold = hold
        running = true
        generation = UUID()
        try recordSegment()
    }

    private func recordSegment() throws {
        guard running else { return }
        let token = generation
        endpoint = SpeechEndpoint(silenceDuration: silenceDuration, now: now, usesSpeechClassification: true)
        try capture.start(recording: true, onSample: { [weak self] power, rms, timestamp in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.recording, self.generation == token else { return }
                self.lastAudioSample = timestamp
                self.onLevel?(min(1, rms * 8))
                self.endpoint.observe(powerDB: power, now: timestamp)
            }
        }, onSpeech: { [weak self] probability, timestamp in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.recording, self.generation == token else { return }
                self.endpoint.observeSpeech(probability: probability, through: timestamp)
            }
        }, onFailure: { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.generation == token else { return }
                self.fail(message)
            }
        })
        recording = true
        lastAudioSample = now
        onTranscribing?(false)
        onStatus?("Listening · pause for \(String(format: "%.1f", silenceDuration)) seconds to send")
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard let self, self.running, self.recording else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard running, recording else { return }
        switch endpoint.state(now: now) {
        case .idleTimeout:
            stop()
            onFinished?()
            onStatus?("No speech heard · press Start listening to try again")
            return
        case .durationLimit:
            fail("This request reached the three-minute recording limit. Try a shorter request.")
            return
        case .finished where !hold:
            finish()
            return
        case .speaking:
            onStatus?("Hearing you…")
        case .pausing:
            onStatus?("Waiting for your pause…")
        default:
            break
        }
        if now - lastAudioSample >= 2 {
            fail("The microphone stopped delivering audio. Check your input device and try again.")
        }
    }

    private func closeRecording() {
        recording = false
        timer?.cancel()
        timer = nil
        segments += capture.finish()
        onLevel?(0)
    }

    func finish() {
        guard running, recording else { return }
        closeRecording()
        onLevel?(0)
        guard endpoint.hasSpeech else {
            stop()
            onFinished?()
            onStatus?("No speech heard · press Start listening to try again")
            return
        }
        guard let transcribe else { fail("Configure cloud transcription in Settings."); return }
        let token = generation
        let recordings = segments
        onTranscribing?(true)
        onStatus?("Microphone off · transcribing your request…")
        task = Task { [weak self] in
            guard let self else { return }
            var text = ""
            do {
                for recording in recordings {
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    let data = try Data(contentsOf: recording)
                    let part = try await transcribe(data).trimmingCharacters(in: .whitespacesAndNewlines)
                    try Task.checkCancellation()
                    guard self.generation == token else { return }
                    text = [text, part].filter { !$0.isEmpty }.joined(separator: " ")
                    guard text.count <= 16000 else { throw Newtv1Failure("The transcript is too long. Try a shorter request.") }
                    try? FileManager.default.removeItem(at: recording)
                }
                guard self.running, self.generation == token else { return }
                self.segments = []
                guard !text.isEmpty else {
                    self.stop()
                    self.onFinished?()
                    self.onStatus?("No words recognized · check your microphone and try again")
                    return
                }
                self.onText?(text)
                guard self.running, self.generation == token else { return }
                if self.continuousListening, !self.hold {
                    self.endpoint = SpeechEndpoint(silenceDuration: self.silenceDuration, now: self.now)
                    try self.recordSegment()
                } else {
                    self.stop()
                    self.onFinished?()
                }
            } catch {
                if self.generation == token, !Task.isCancelled { self.fail(error.localizedDescription) }
            }
        }
    }

    func stop() {
        running = false
        generation = UUID()
        task?.cancel()
        task = nil
        timer?.cancel()
        timer = nil
        recording = false
        capture.discard()
        onTranscribing?(false)
        for segment in segments { try? FileManager.default.removeItem(at: segment) }
        segments = []
        onLevel?(0)
    }

    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }
}

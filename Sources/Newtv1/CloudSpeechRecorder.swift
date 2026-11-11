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
    var silenceDuration: TimeInterval = 1.4
    var continuousListening = false
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var file: URL?
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
        endpoint = SpeechEndpoint(silenceDuration: silenceDuration, now: now)
        try recordSegment()
    }

    private func recordSegment() throws {
        guard running else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("newtv1-" + UUID().uuidString + ".wav")
        file = url
        do {
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord() else { throw Newtv1Failure("The microphone recorder could not prepare.") }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            guard recorder.record() else { throw Newtv1Failure("The microphone recorder could not start.") }
            self.recorder = recorder
            onStatus?("Listening · finish speaking to send")
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
        } catch {
            stop()
            throw error
        }
    }

    private func tick() {
        guard running, let recorder else { return }
        guard recorder.isRecording else {
            fail("The microphone recording was interrupted. Check your input device and try again.")
            return
        }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        onLevel?(min(1, pow(10, power / 20) * 4))
        endpoint.observe(powerDB: Double(power), now: now)
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
            onStatus?("Waiting for you to finish…")
        default:
            break
        }
        // Keep each provider upload bounded without dispatching an incomplete command.
        if recorder.currentTime >= 28 {
            closeSegment()
            do { try recordSegment() }
            catch { fail("Microphone recording was interrupted. Try again.") }
        }
    }

    private func closeSegment() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        if let file { segments.append(file) }
        file = nil
    }

    func finish() {
        guard running, recorder != nil else { return }
        closeSegment()
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
        onStatus?("Transcribing your complete request…")
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
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        for segment in segments { try? FileManager.default.removeItem(at: segment) }
        segments = []
        onLevel?(0)
    }

    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }
}

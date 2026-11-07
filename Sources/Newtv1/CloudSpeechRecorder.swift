import AppKit
import AVFoundation

@MainActor
final class CloudSpeechRecorder {
    var onText: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((String) -> Void)?
    var onFinished: (() -> Void)?
    var transcribe: ((Data) async throws -> String)?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var file: URL?
    private var running = false
    private var hold = false
    private var sawVoice = false
    private var lastVoice = Date()
    private var task: Task<Void, Never>?
    private var generation = UUID()
    func start(hold: Bool) throws {
        stop(); self.hold = hold; running = true; generation = UUID()
        try record()
    }
    private func record() throws {
        guard running else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("newtv1-" + UUID().uuidString + ".wav")
        file = url
        do {
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else { throw Newtv1Failure("The microphone recorder could not start.") }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            self.recorder = recorder; sawVoice = false; lastVoice = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        } catch { cleanup(); throw error }
    }
    private func tick() {
        guard running, let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        onLevel?(min(1, pow(10, power / 20) * 4))
        if power > -42 { sawVoice = true; lastVoice = Date() }
        if !hold, sawVoice, Date().timeIntervalSince(lastVoice) >= 1.2, recorder.currentTime > 0.4 { finish(); return }
        if recorder.currentTime >= 28 {
            if sawVoice { finish() }
            else { cleanup(); do { try record() } catch { fail(error.localizedDescription) } }
        }
    }
    func finish() {
        guard running, let recorder else { return }
        let enough = sawVoice && recorder.currentTime > 0.3
        recorder.stop(); timer?.invalidate(); timer = nil; self.recorder = nil
        let token = generation
        guard enough, let file, let transcribe else {
            cleanup()
            if hold { running = false; onFinished?() }
            else { do { try record() } catch { fail(error.localizedDescription) } }
            return
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: file)
                try? FileManager.default.removeItem(at: file); self.file = nil
                self.onLevel?(0)
                let text = try await transcribe(data)
                try Task.checkCancellation()
                guard self.running, self.generation == token else { return }
                if !text.isEmpty { self.onText?(text) }
                guard self.running, self.generation == token else { return }
                if self.hold { self.running = false; self.onFinished?() }
                else { try self.record() }
            } catch {
                if self.generation == token, !Task.isCancelled { self.fail(error.localizedDescription) }
            }
        }
    }
    func stop() { running = false; generation = UUID(); task?.cancel(); task = nil; cleanup(); onLevel?(0) }
    private func cleanup() { timer?.invalidate(); timer = nil; recorder?.stop(); recorder = nil; if let file { try? FileManager.default.removeItem(at: file) }; file = nil }
    private func fail(_ message: String) { stop(); onFailure?(message) }
}

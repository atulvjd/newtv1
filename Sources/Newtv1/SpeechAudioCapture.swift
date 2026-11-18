import AVFoundation
import SoundAnalysis

private struct SpeechCaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One microphone stream for recognition, on-device voice detection and optional WAV capture.
/// Sound classification and disk work run on a serial queue, never on the main thread.
@MainActor
final class SpeechAudioCapture {
    private let engine = AVAudioEngine()
    private var stream: SpeechAudioStream?
    private var tapInstalled = false

    func start(recording: Bool, onBuffer: ((AVAudioPCMBuffer) -> Void)? = nil,
               onSample: @escaping (Double, Float, TimeInterval) -> Void,
               onSpeech: @escaping (Double, TimeInterval) -> Void,
               onFailure: @escaping (String) -> Void) throws {
        discard()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechCaptureError(message: "No working microphone found. Check your input device in Sound settings.")
        }
        let stream = try SpeechAudioStream(format: format, recording: recording,
            startedAt: ProcessInfo.processInfo.systemUptime, onSample: onSample,
            onSpeech: onSpeech, onFailure: onFailure)
        self.stream = stream
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer?(buffer)
            stream.append(buffer, at: ProcessInfo.processInfo.systemUptime)
        }
        tapInstalled = true
        do { engine.prepare(); try engine.start() }
        catch { discard(); throw error }
    }

    /// Close the microphone before draining the audio queue and returning sealed recordings.
    func finish() -> [URL] {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        let recordings = stream?.finish() ?? []
        stream = nil
        return recordings
    }

    func discard() {
        for file in finish() { try? FileManager.default.removeItem(at: file) }
    }
}

/// Also accepts file buffers, so speech/noise endpointing and WAV conversion can be checked
/// without opening a microphone or sending audio to a provider.
final class SpeechAudioStream {
    private let queue = DispatchQueue(label: "dev.newtv1.speech-audio", qos: .userInitiated)
    private let analyzer: SNAudioStreamAnalyzer
    private let observer: SpeechSoundObserver
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let onSample: (Double, Float, TimeInterval) -> Void
    private let onFailure: (String) -> Void
    private var framePosition: AVAudioFramePosition = 0
    private var writer: AVAudioFile?
    private var recordings: [URL] = []
    private var closed = false
    private var failed = false
    private var lastMeterSample = -Double.infinity

    init(format: AVAudioFormat, recording: Bool, startedAt: TimeInterval,
         onSample: @escaping (Double, Float, TimeInterval) -> Void,
         onSpeech: @escaping (Double, TimeInterval) -> Void,
         onFailure: @escaping (String) -> Void) throws {
        self.onSample = onSample
        self.onFailure = onFailure
        outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        converter = recording ? AVAudioConverter(from: format, to: outputFormat) : nil
        if recording, converter == nil { throw SpeechCaptureError(message: "Cannot convert this microphone's audio format.") }
        analyzer = SNAudioStreamAnalyzer(format: format)
        observer = SpeechSoundObserver(startedAt: startedAt, onSpeech: onSpeech, onFailure: onFailure)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 48000)
        request.overlapFactor = 0.75
        try analyzer.add(request, withObserver: observer)
    }

    func append(_ buffer: AVAudioPCMBuffer, at timestamp: TimeInterval) {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (input, output) in zip(source, destination) {
            if let from = input.mData, let to = output.mData { memcpy(to, from, Int(min(input.mDataByteSize, output.mDataByteSize))) }
        }
        queue.async { [self] in
            guard !closed, !failed else { return }
            if let channel = copy.floatChannelData?[0] {
                var sum: Float = 0
                for index in 0..<Int(copy.frameLength) { sum += channel[index] * channel[index] }
                let rms = sqrt(sum / Float(copy.frameLength))
                // Retain all audio for recognition/classification, but bound UI
                // meter work to 20 Hz instead of scheduling every tap buffer.
                if timestamp - lastMeterSample >= 0.05 {
                    onSample(Double(20 * log10(max(rms, 0.00001))), rms, timestamp)
                    lastMeterSample = timestamp
                }
            }
            do { try convert(copy) }
            catch { failed = true; onFailure("Microphone recording could not be saved. Try again."); return }
            if framePosition == 0 { observer.startedAt = timestamp - Double(copy.frameLength) / copy.format.sampleRate }
            analyzer.analyze(copy, atAudioFramePosition: framePosition)
            framePosition += AVAudioFramePosition(copy.frameLength)
        }
    }

    private func convert(_ input: AVAudioPCMBuffer) throws {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw SpeechCaptureError(message: "Cannot allocate microphone audio.")
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if let error { throw error }
        if status == .error { throw SpeechCaptureError(message: "Microphone conversion failed.") }
        try write(output)
    }

    private func write(_ buffer: AVAudioPCMBuffer) throws {
        guard buffer.frameLength > 0 else { return }
        if writer == nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("newtv1-\(UUID().uuidString).wav")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            recordings.append(url)
            writer = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        try writer?.write(from: buffer)
        // Rotate only the file, keeping voice detection and microphone audio continuous.
        if let writer, writer.length >= 28 * 16000 { self.writer = nil }
    }

    func finish() -> [URL] {
        queue.sync {
            guard !closed else { return [] }
            closed = true
            // Drain the resampler's small tail before closing the last WAV.
            if let converter, let tail = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1024), !failed {
                var error: NSError?
                for _ in 0..<4 {
                    tail.frameLength = 0
                    let status = converter.convert(to: tail, error: &error) { _, state in state.pointee = .endOfStream; return nil }
                    if error != nil || status == .error { break }
                    do { try write(tail) } catch { onFailure("Microphone recording could not be finalized."); break }
                    if status == .endOfStream || tail.frameLength == 0 { break }
                }
            }
            analyzer.removeAllRequests()
            writer = nil
            let result = recordings
            recordings = []
            return result
        }
    }
}

private final class SpeechSoundObserver: NSObject, SNResultsObserving {
    var startedAt: TimeInterval
    private let onSpeech: (Double, TimeInterval) -> Void
    private let onFailure: (String) -> Void
    init(startedAt: TimeInterval, onSpeech: @escaping (Double, TimeInterval) -> Void, onFailure: @escaping (String) -> Void) {
        self.startedAt = startedAt; self.onSpeech = onSpeech; self.onFailure = onFailure
    }
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let confidence = result.classifications.filter { $0.identifier == "speech" || $0.identifier == "whispering" }.map(\.confidence).max() ?? 0
        onSpeech(confidence, startedAt + CMTimeGetSeconds(CMTimeRangeGetEnd(result.timeRange)))
    }
    func request(_ request: SNRequest, didFailWithError error: Error) {
        onFailure("Voice detection was interrupted. Check your input device and try again.")
    }
    func requestDidComplete(_ request: SNRequest) {}
}

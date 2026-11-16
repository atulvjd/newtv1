import AVFoundation
import Foundation

// Compile alongside SpeechAudioCapture.swift and SpeechEndpoint.swift. No microphone,
// provider credentials or network access are used. Pass a local spoken-audio fixture.
@main
struct SpeechAudioChecks {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass a local spoken-audio fixture.") }
        let source = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[1]))
        let format = source.processingFormat
        let speech = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(source.length))!
        try source.read(into: speech)
        let speechDuration = Double(speech.frameLength) / format.sampleRate
        var endpoint = SpeechEndpoint(now: 0, usesSpeechClassification: true)
        var events = 0
        var firstFinish: Double?
        var failures: [String] = []
        var strongestSpeech = 0.0
        let speechStart = 1.0
        let speechEnd = speechStart + speechDuration
        let stream = try SpeechAudioStream(format: format, recording: true, startedAt: 0,
            onSample: { power, _, time in
                endpoint.observe(powerDB: power, now: time)
                if endpoint.state(now: time) == .finished, firstFinish == nil { firstFinish = time }
            }, onSpeech: { probability, time in
                events += 1
                endpoint.observeSpeech(probability: probability, through: time)
                if time > speechStart, time < speechEnd { strongestSpeech = max(strongestSpeech, probability) }
            }, onFailure: { failures.append($0) })
        var clock = 0.0
        var random: UInt64 = 42
        func noise(_ duration: Double) {
            var remaining = Int(duration * format.sampleRate)
            while remaining > 0 {
                let count = min(1024, remaining)
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                for channel in 0..<Int(format.channelCount) {
                    for index in 0..<count {
                        random = random &* 6364136223846793005 &+ 1
                        let hiss = Float(Double(random >> 40) / Double(1 << 24) * 2 - 1)
                        buffer.floatChannelData![channel][index] = Float(sin((clock + Double(index) / format.sampleRate) * 2 * .pi * 120)) * 0.035 + hiss * 0.005
                    }
                }
                clock += Double(count) / format.sampleRate
                stream.append(buffer, at: clock)
                remaining -= count
            }
        }
        noise(speechStart)
        // Split the actual speech into the same small buffers used by microphone capture.
        var position = 0
        while position < Int(speech.frameLength) {
            let count = min(1024, Int(speech.frameLength) - position)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            buffer.frameLength = AVAudioFrameCount(count)
            for channel in 0..<Int(format.channelCount) {
                buffer.floatChannelData![channel].update(from: speech.floatChannelData![channel] + position, count: count)
            }
            clock += Double(count) / format.sampleRate
            stream.append(buffer, at: clock)
            position += count
        }
        noise(4)
        let recordings = stream.finish()
        defer { for file in recordings { try? FileManager.default.removeItem(at: file) } }
        precondition(failures.isEmpty, "Audio analysis/conversion failed: \(failures)")
        precondition(events > 0 && strongestSpeech >= 0.4, "Speech classifier didn't recognize the spoken fixture")
        guard let firstFinish else { fatalError("Steady background noise kept the microphone open indefinitely") }
        precondition(firstFinish >= speechEnd - 0.3, "Premature endpoint while speech was still playing")
        precondition(firstFinish <= speechEnd + 2.75, "Endpoint wasn't reached after two seconds without speech")
        var savedFrames: AVAudioFramePosition = 0
        for url in recordings {
            let data = try Data(contentsOf: url)
            precondition(data.count < 2_000_000 && String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
            let file = try AVAudioFile(forReading: url)
            precondition(file.fileFormat.sampleRate == 16000 && file.fileFormat.channelCount == 1)
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            precondition(permissions?.intValue == 0o600)
            savedFrames += file.length
        }
        precondition(abs(Double(savedFrames) / 16000 - clock) < 0.02, "WAV conversion dropped audio")
        print(String(format: "Speech + fan-noise fixture passed: endpoint %.2f s after spoken audio; %d classifier windows; mono 16 kHz WAV verified.", firstFinish - speechEnd, events))

        // Stereo 48 kHz -> mono 16 kHz, >28-second requests, and no false speech on hum.
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        var noiseSpeech = 0.0
        let long = try SpeechAudioStream(format: stereo, recording: true, startedAt: 0,
            onSample: { _, _, _ in }, onSpeech: { probability, _ in noiseSpeech = max(noiseSpeech, probability) },
            onFailure: { failures.append($0) })
        var elapsed = 0.0
        for _ in 0..<1500 {
            let buffer = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 1024)!
            buffer.frameLength = 1024
            for index in 0..<1024 {
                let value = Float(sin((elapsed + Double(index) / 48000) * 2 * .pi * 120)) * 0.035
                buffer.floatChannelData![0][index] = value
                buffer.floatChannelData![1][index] = value * 0.8
            }
            elapsed += 1024.0 / 48000
            long.append(buffer, at: elapsed)
        }
        let parts = long.finish()
        defer { for file in parts { try? FileManager.default.removeItem(at: file) } }
        precondition(parts.count == 2 && failures.isEmpty, "Recording rotation failed")
        var total: AVAudioFramePosition = 0
        for url in parts {
            let data = try Data(contentsOf: url)
            precondition(data.count < 2_000_000)
            let file = try AVAudioFile(forReading: url)
            total += file.length
        }
        precondition(abs(Double(total) / 16000 - elapsed) < 0.02)
        precondition(noiseSpeech < 0.4, "Steady hum was classified as voice")
        precondition(long.finish().isEmpty, "Recording finish must be idempotent")
        print("48 kHz stereo fixture passed: bounded WAV rotation, continuous conversion, no speech from steady hum.")
    }
}

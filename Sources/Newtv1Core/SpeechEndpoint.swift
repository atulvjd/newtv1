import Foundation

/// Acoustic endpoint detection shared by local recognition and cloud recording.
/// Times are monotonic seconds. A transcript update alone never ends an utterance.
public struct SpeechEndpoint {
    public enum State: Equatable { case waiting, speaking, pausing, finished, idleTimeout, durationLimit }
    public let silenceDuration: TimeInterval
    private let startedAt: TimeInterval
    private var previousSample: TimeInterval
    private var noiseFloor: Double = -60
    private var voicedDuration: TimeInterval = 0
    private var candidateDuration: TimeInterval = 0
    private var lastVoice: TimeInterval?
    private var lastTextChange: TimeInterval?
    private var voiceActive = false
    public private(set) var hasSpeech = false

    public init(silenceDuration: TimeInterval = 1.4, now: TimeInterval) {
        self.silenceDuration = silenceDuration.isFinite ? min(3, max(0.6, silenceDuration)) : 1.4
        startedAt = now
        previousSample = now
    }

    public mutating func observe(powerDB: Double, now: TimeInterval) {
        guard now.isFinite, powerDB.isFinite, now >= previousSample else { return }
        let elapsed = min(0.2, now - previousSample)
        previousSample = now
        let threshold = min(-28, max(-52, noiseFloor + 10))
        let voiced = powerDB > threshold - (voiceActive ? 4 : 0)
        if voiced {
            candidateDuration += elapsed
            voicedDuration += elapsed
            if candidateDuration >= 0.12 {
                voiceActive = true
                hasSpeech = true
                lastVoice = now
            }
        } else {
            candidateDuration = 0
            voiceActive = false
            // Learn ambient noise only from quiet frames, avoiding the speaker's voice.
            let weight = 1 - exp(-elapsed / 1.5)
            noiseFloor += weight * (max(-80, powerDB) - noiseFloor)
        }
    }

    public mutating func transcriptChanged(now: TimeInterval) {
        lastTextChange = now
        hasSpeech = true
        lastVoice = max(lastVoice ?? now, now)
    }

    public func state(now: TimeInterval) -> State {
        if now - startedAt >= 180 { return .durationLimit }
        guard hasSpeech else { return now - startedAt >= 12 ? .idleTimeout : .waiting }
        if voiceActive { return .speaking }
        let quiet = now - (lastVoice ?? startedAt)
        let stableText = lastTextChange.map { now - $0 >= 0.35 } ?? true
        if quiet >= silenceDuration, stableText, voicedDuration >= 0.12 || lastTextChange != nil { return .finished }
        return .pausing
    }
}

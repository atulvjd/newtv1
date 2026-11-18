import Foundation

/// Acoustic endpoint detection shared by local recognition and cloud recording.
/// Times are monotonic seconds. Transcription latency must not extend acoustic silence.
public struct SpeechEndpoint {
    public enum State: Equatable { case waiting, speaking, pausing, finished, idleTimeout, durationLimit }
    public let silenceDuration: TimeInterval
    private let startedAt: TimeInterval
    private var previousSample: TimeInterval
    private var noiseFloor: Double = -60
    private var candidateDuration: TimeInterval = 0
    private var lastVoice: TimeInterval?
    private var lastClassification: TimeInterval?
    private var lastAudibleSample: TimeInterval?
    private var classifiedVoice = false
    private let usesSpeechClassification: Bool
    private var voiceActive = false
    public private(set) var hasSpeech = false

    public init(silenceDuration: TimeInterval = 2, now: TimeInterval, usesSpeechClassification: Bool = false) {
        self.silenceDuration = silenceDuration.isFinite ? min(3, max(0.6, silenceDuration)) : 2
        self.usesSpeechClassification = usesSpeechClassification
        startedAt = now
        previousSample = now
    }

    public mutating func observe(powerDB: Double, now: TimeInterval) {
        guard now.isFinite, powerDB.isFinite, now >= previousSample else { return }
        let elapsed = min(0.2, now - previousSample)
        previousSample = now
        if powerDB > -70 { lastAudibleSample = now }
        let threshold = min(-28, max(-52, noiseFloor + 10))
        let voiced = powerDB > threshold - (voiceActive ? 4 : 0)
        if voiced {
            candidateDuration += elapsed
            if candidateDuration >= 0.12 {
                voiceActive = true
                if !usesSpeechClassification {
                    hasSpeech = true
                    lastVoice = now
                }
            }
        } else {
            candidateDuration = 0
            voiceActive = false
            // Learn ambient noise only from quiet frames, avoiding the speaker's voice.
            let weight = 1 - exp(-elapsed / 1.5)
            noiseFloor += weight * (max(-80, powerDB) - noiseFloor)
        }
    }

    /// `through` is the end of the classified audio window, not the callback's arrival time.
    /// Background fans, clicks and music must not continually reset the voice deadline.
    public mutating func observeSpeech(probability: Double, through: TimeInterval) {
        guard usesSpeechClassification, probability.isFinite, through.isFinite,
              through >= startedAt, through >= (lastClassification ?? startedAt) else { return }
        lastClassification = through
        // A speech label cannot keep capture alive over digital silence or a
        // muted input. Classifier windows may still include earlier speech.
        let audible = lastAudibleSample.map { through - $0 <= 0.5 && through >= $0 - 0.5 } ?? false
        classifiedVoice = audible && probability >= (classifiedVoice ? 0.25 : 0.4)
        if classifiedVoice {
            hasSpeech = true
            let voiceEnd = min(through, lastAudibleSample ?? through)
            lastVoice = max(lastVoice ?? voiceEnd, voiceEnd)
        }
    }

    public mutating func transcriptChanged(now: TimeInterval) {
        guard now.isFinite, now >= startedAt else { return }
        hasSpeech = true
        // A late partial, punctuation correction or final result isn't new microphone audio.
        if lastVoice == nil { lastVoice = min(now, previousSample) }
    }

    /// Recognizer word timings refer to captured audio, rather than delivery time.
    /// This rescues quiet speech missed by sound classification without allowing
    /// late punctuation/partial callbacks to keep a silent microphone open.
    public mutating func recognizedSpeech(through: TimeInterval) {
        guard through.isFinite, through >= startedAt, through <= previousSample else { return }
        hasSpeech = true
        lastVoice = max(lastVoice ?? through, through)
    }

    public func state(now: TimeInterval) -> State {
        if now - startedAt >= 180 { return .durationLimit }
        guard hasSpeech else { return now - startedAt >= 12 ? .idleTimeout : .waiting }
        if usesSpeechClassification {
            if classifiedVoice, now - (lastClassification ?? startedAt) < 0.6 { return .speaking }
        } else if voiceActive, now - previousSample < 0.3 { return .speaking }
        let quiet = now - (lastVoice ?? startedAt)
        if quiet >= silenceDuration { return .finished }
        return .pausing
    }
}

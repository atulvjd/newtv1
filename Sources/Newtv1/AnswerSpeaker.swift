import AppKit
import AVFoundation
import NaturalLanguage

@MainActor
final class AnswerSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speaking = false
    @Published private(set) var caption = ""
    private let synthesizer = AVSpeechSynthesizer()
    private var current: AVSpeechUtterance?
    var onFinished: (() -> Void)?
    override init() { super.init(); synthesizer.delegate = self }

    func speak(_ markdown: String, voiceID: String, rate: Double) {
        stop()
        var text = markdown.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[`#*_]"#, with: "", options: .regularExpression)
        let utterance = AVSpeechUtterance(string: String(text.prefix(7000)))
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID) ?? AVSpeechSynthesisVoice(language: NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? Locale.current.identifier)
        utterance.rate = Float(max(0.3, min(rate, 0.65)))
        current = utterance; caption = String(text.prefix(120)); speaking = true; synthesizer.speak(utterance)
    }
    func stop() { caption = ""; current = nil; synthesizer.stopSpeaking(at: .immediate); speaking = false }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let text = utterance.speechString as NSString
        let start = max(0, characterRange.location - 45)
        let end = min(text.length, characterRange.location + characterRange.length + 90)
        let safe = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: max(0, end - start)))
        let snippet = text.substring(with: safe)
        Task { @MainActor [weak self] in guard let self, self.current === utterance else { return }; self.caption = snippet }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in guard let self, self.current === utterance else { return }; self.current = nil; self.caption = ""; self.speaking = false; self.onFinished?() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in guard self?.current === utterance else { return }; self?.current = nil; self?.caption = ""; self?.speaking = false }
    }
}

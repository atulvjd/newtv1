import Foundation

public enum VoiceCommand {
    public static func phrases(custom: String = "") -> [String] {
        var words = custom.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > 1, words.first?.lowercased() == "hey" { words.removeFirst() }
        return words.isEmpty ? ["Newt", "New"] : [words.joined(separator: " ")]
    }

    public static func recognitionPhrases(custom: String = "") -> [String] {
        let base = phrases(custom: custom)
        return base + base.map { "Hey \($0)" }
    }

    public static func extract(_ raw: String, requireWakePhrase: Bool, custom: String = "") -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // “New” must not accidentally retain the old “New TV One” wake phrase.
        if custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           text.range(of: #"^(?:hey[\s,]+)?new\s*tv\s*(?:one|1)(?:[\s,.:]|$)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return requireWakePhrase ? nil : text
        }
        let names = phrases(custom: custom).map { phrase in
            phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s+"#)
        }.joined(separator: "|")
        let pattern = #"^(?:hey[\s,]+)?(?:"# + names + #")[\s,.:]+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let command = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return command.isEmpty ? nil : command
        }
        return requireWakePhrase || text.isEmpty ? nil : text
    }
}

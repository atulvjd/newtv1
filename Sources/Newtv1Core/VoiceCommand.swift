import Foundation

public enum VoiceCommand {
    /// Recognizers may render the product name as either “Newtv1” or “New TV One”.
    public static func extract(_ raw: String, requireWakePhrase: Bool) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:hey[\s,]+)?(?:newtv1|new\s*tv\s*(?:one|1))[\s,.:]+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let command = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return command.isEmpty ? nil : command
        }
        return requireWakePhrase || text.isEmpty ? nil : text
    }
}

import Foundation

public struct LyricLine: Equatable, Identifiable {
    public let id: Int
    public let seconds: Double
    public let text: String
}
public enum Lyrics {
    public static func parse(_ text: String) throws -> [LyricLine] {
        guard text.utf8.count <= 128000 else { throw CommandError.invalid("Lyrics must be under 128 KB.") }
        let regex = try NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        var offset = 0.0
        if let match = offsetPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text), let value = Double(text[range]), abs(value) <= 60000 { offset = value / 1000 }
        var output: [(Double,String)] = []
        for line in text.components(separatedBy: .newlines) {
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard let last = matches.last, let end = Range(last.range, in: line)?.upperBound else { continue }
            let content = String(line[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard content.count <= 500 else { throw CommandError.invalid("A lyric line is too long.") }
            for match in matches {
                func value(_ index: Int) -> String { Range(match.range(at: index), in: line).map { String(line[$0]) } ?? "" }
                let minute = Double(value(1)) ?? 0; let second = Double(value(2)) ?? 0; let fraction = value(3)
                guard second < 60 else { continue }
                let time = minute * 60 + second + (Double("0." + fraction) ?? 0) + offset
                output.append((max(0,time),content))
            }
            guard output.count <= 2000 else { throw CommandError.invalid("Lyrics contain too many timestamps.") }
        }
        guard !output.isEmpty else { throw CommandError.invalid("No timed LRC lyrics were found.") }
        return output.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, seconds: $0.element.0, text: $0.element.1) }
    }
    public static func current(in lines: [LyricLine], at seconds: Double) -> LyricLine? { guard seconds.isFinite else { return nil }; return lines.last { $0.seconds <= seconds } }
}

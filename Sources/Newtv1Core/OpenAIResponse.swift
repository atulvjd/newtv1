import Foundation

public struct BrainDecision: Decodable {
    public let intent: String
    public let answer: String
    public let search_query: String
    public let commands: [String]

    public func actionPlan(transcript: String, workflows: [Workflow]) throws -> CommandPlan {
        guard intent == "actions", !commands.isEmpty else { throw CommandError.invalid("The brain did not propose any Mac actions.") }
        let data = try JSONSerialization.data(withJSONObject: ["commands": commands, "explanation": answer])
        return try JSONDecoder().decode(ModelPlan.self, from: data).validated(transcript: transcript, workflows: workflows)
    }
}

public struct OpenAIResponse: Decodable {
    public struct Item: Decodable {
        public struct Content: Decodable {
            public struct Citation: Decodable {
                public let type: String
                public let url: String?
                public let title: String?
                public let start_index: Int?
                public let end_index: Int?
            }
            public let type: String
            public let text: String?
            public let refusal: String?
            public let annotations: [Citation]?

            public var markdown: String {
                guard var result = text else { return "" }
                let scalars = result.unicodeScalars
                let citations = (annotations ?? []).filter { $0.type == "url_citation" }.sorted { ($0.start_index ?? 0) > ($1.start_index ?? 0) }
                var previousStart = scalars.count
                for citation in citations {
                    guard let urlString = citation.url, let url = URL(string: urlString), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                          let start = citation.start_index, let end = citation.end_index,
                          start >= 0, start < end, end <= scalars.count, end <= previousStart else { continue }
                    let from = result.unicodeScalars.index(result.unicodeScalars.startIndex, offsetBy: start)
                    let to = result.unicodeScalars.index(result.unicodeScalars.startIndex, offsetBy: end)
                    let title = (citation.title ?? url.host ?? "Source").replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "").replacingOccurrences(of: "\n", with: " ")
                    let destination = url.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
                    result.replaceSubrange(from..<to, with: "[\(title)](\(destination))")
                    previousStart = start
                }
                return result
            }
        }
        public let type: String
        public let content: [Content]?
    }
    public let status: String?
    public let output: [Item]?

    public func text(markdown: Bool = false) throws -> String {
        guard status == "completed" else { throw CommandError.invalid("The AI response did not complete. Try a shorter request.") }
        let contents = (output ?? []).filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        if let refusal = contents.first(where: { $0.type == "refusal" })?.refusal { throw CommandError.invalid(refusal) }
        let result = contents.filter { $0.type == "output_text" }.map { markdown ? $0.markdown : ($0.text ?? "") }.joined(separator: "\n")
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CommandError.invalid("The brain returned no answer.") }
        return result
    }
}

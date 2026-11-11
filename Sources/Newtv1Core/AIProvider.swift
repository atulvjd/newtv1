import Foundation

public enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "openai", gemini
    public var id: String { rawValue }
    public var title: String { self == .gemini ? "Gemini" : "OpenAI" }
    public var defaultModel: String { self == .gemini ? "gemini-2.5-flash" : "gpt-5.4-mini" }
    public var keyFlag: String { self == .gemini ? "geminiKeyConfigured" : "openAIKeyConfigured" }
}

/// Converts Newt's shared prompt/schema envelope to Gemini's native REST format.
/// Local command, diagram and coordinate validation still runs after decoding.
public enum GeminiPayload {
    public static func request(_ body: [String: Any]) throws -> [String: Any] {
        func parts(_ value: Any?) throws -> [[String: Any]] {
            if let text = value as? String { return [["text": text]] }
            guard let content = value as? [[String: Any]] else { throw CommandError.invalid("Unsupported Gemini input.") }
            return try content.map { part in
                switch part["type"] as? String {
                case "input_text": return ["text": part["text"] as? String ?? ""]
                case "input_image":
                    guard let value = part["image_url"] as? String, value.hasPrefix("data:image/jpeg;base64,"), let encoded = value.split(separator: ",", maxSplits: 1).last else { throw CommandError.invalid("Unsupported Gemini image input.") }
                    return ["inlineData": ["mimeType": "image/jpeg", "data": String(encoded)]]
                case "input_audio": return ["inlineData": ["mimeType": "audio/wav", "data": part["data"] as? String ?? ""]]
                default: throw CommandError.invalid("Unsupported Gemini content part.")
                }
            }
        }
        let contents: [[String: Any]]
        if let text = body["input"] as? String { contents = [["role": "user", "parts": [["text": text]]]] }
        else if let turns = body["input"] as? [[String: Any]] {
            contents = try turns.map { ["role": ($0["role"] as? String == "assistant" ? "model" : "user"), "parts": try parts($0["content"])] }
        } else { throw CommandError.invalid("No Gemini input.") }
        var config: [String: Any] = ["maxOutputTokens": body["max_output_tokens"] as? Int ?? 2500]
        if (body["model"] as? String ?? "").hasPrefix("gemini-2.5-flash") { config["thinkingConfig"] = ["thinkingBudget": 0] }
        if let format = (body["text"] as? [String: Any])?["format"] as? [String: Any], let schema = format["schema"] {
            config["responseMimeType"] = "application/json"; config["responseJsonSchema"] = schema
        }
        var result: [String: Any] = ["contents": contents, "generationConfig": config, "systemInstruction": ["parts": [["text": body["instructions"] as? String ?? "You are Newt."]]]]
        if body["tools"] != nil { result["tools"] = [["google_search": [:] as [String: String]]] }
        return result
    }
    public static func response(_ data: Data) throws -> OpenAIResponse {
        guard data.count < 2_000_000, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CommandError.invalid("Invalid Gemini response.") }
        guard (root["promptFeedback"] as? [String: Any])?["blockReason"] == nil,
              let candidate = (root["candidates"] as? [[String: Any]])?.first,
              candidate["finishReason"] as? String == "STOP" else { throw CommandError.invalid("Gemini did not complete the response or declined it. Try a shorter or different request.") }
        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        var text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CommandError.invalid("Gemini returned no answer.") }
        let metadata = candidate["groundingMetadata"] as? [String: Any] ?? [:]
        var links: [String] = [], seen = Set<String>()
        for chunk in (metadata["groundingChunks"] as? [[String: Any]] ?? []).prefix(20) {
            guard let web = chunk["web"] as? [String: Any], let address = web["uri"] as? String,
                  let url = URL(string: address), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, seen.insert(address).inserted else { continue }
            let title = String((web["title"] as? String ?? url.host ?? "Source").prefix(200)).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "").replacingOccurrences(of: "\n", with: " ")
            links.append("[" + title + "](" + address.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29") + ")")
        }
        if !links.isEmpty { text += "\n\nSources: " + links.joined(separator: ", ") }
        let envelope: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        return try JSONDecoder().decode(OpenAIResponse.self, from: JSONSerialization.data(withJSONObject: envelope))
    }
}

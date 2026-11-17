import Foundation

public struct ChatGPTModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
    public static func decode(_ data: Data) throws -> [ChatGPTModel] {
        guard data.count <= 1_000_000, let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let models = root["models"] as? [[String: Any]], models.count <= 500 else { throw CommandError.invalid("ChatGPT returned an invalid model list.") }
        var seen: Set<String> = []
        return models.compactMap { model in
            guard model["visibility"] as? String == "list", let slug = model["slug"] as? String, !slug.isEmpty, slug.count < 100,
                  slug.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._".contains($0)) }), seen.insert(slug).inserted else { return nil }
            return ChatGPTModel(id: slug, name: String((model["display_name"] as? String ?? slug).prefix(150)))
        }
    }
}

public enum ChatGPTPayload {
    /// The ChatGPT-plan route requires streaming, explicit history and supported fields only.
    public static func request(_ input: [String: Any]) throws -> [String: Any] {
        let fields: Set<String> = ["model", "input", "instructions", "reasoning", "text", "tools", "tool_choice", "parallel_tool_calls"]
        var body = input.filter { fields.contains($0.key) }
        body["store"] = false; body["stream"] = true
        if let text = input["input"] as? String { body["input"] = [["role": "user", "content": text]] }
        guard let messages = body["input"] as? [[String: Any]], !messages.isEmpty else { throw CommandError.invalid("ChatGPT needs an explicit input message.") }
        for message in messages {
            guard message["role"] as? String != "system" else { throw CommandError.invalid("Use instructions for ChatGPT system context.") }
            if let content = message["content"] as? [[String: Any]] {
                guard content.allSatisfy({ ["input_text", "input_image", "input_file", "output_text"].contains($0["type"] as? String ?? "") }) else { throw CommandError.invalid("ChatGPT plan sign-in does not support audio or video input. Use Apple speech recognition.") }
            }
        }
        if let tools = body["tools"] as? [[String: Any]] {
            guard tools.allSatisfy({ $0["type"] as? String == "web_search" }) else { throw CommandError.invalid("This ChatGPT connection supports Newtv1’s local actions and optional web search, not hosted computer-use or other hosted tools.") }
        }
        return body
    }
    public static func failure(code: String?) -> CommandError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return .invalid("Your ChatGPT plan’s app usage limit was reached. Check ChatGPT Settings → Usage, or wait for it to reset. No action was run.")
        case "subscription_sharing_usage_unavailable": return .invalid("ChatGPT plan usage is unavailable for this account or app. Check the app’s access in ChatGPT Settings → Usage.")
        case "invalid_api_key", "invalid_token", "token_expired": return .invalid("Your ChatGPT session is no longer valid. Reconnect the account in Settings → AI.")
        case "model_not_found", "model_not_available": return .invalid("This ChatGPT account cannot use that model. Refresh the account’s model list in Settings → AI.")
        default: return .invalid("ChatGPT did not complete the request. Check the account’s connection and usage limits, then try again.")
        }
    }
}

/// Does not expose partial JSON plans. Success requires the terminal completed response,
/// including when a plan-limit failure arrives after text has already started streaming.
public struct ChatGPTEventStream {
    private var payload: [String] = []
    private var eventBytes = 0
    private var receivedBytes = 0
    private var items: [Int: [String: Any]] = [:]
    private var parts: [Int: [Int: [String: Any]]] = [:]
    public private(set) var completed = false
    public init() {}
    public mutating func consume(_ line: String) throws -> OpenAIResponse? {
        receivedBytes += line.utf8.count + 1
        guard receivedBytes <= 4_000_000 else { throw CommandError.invalid("ChatGPT’s streamed response exceeded the limit.") }
        if line.isEmpty { return try flush() }
        if line.hasPrefix("data:") {
            let part = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            eventBytes += part.utf8.count
            guard eventBytes <= 2_000_000 else { throw CommandError.invalid("A ChatGPT stream event was too large.") }
            payload.append(part)
        }
        return nil
    }
    public mutating func finish() throws -> OpenAIResponse? {
        let response = try flush()
        guard completed else { throw CommandError.invalid("The ChatGPT response was interrupted before completion. Nothing was executed; retry the request.") }
        return response
    }
    private mutating func flush() throws -> OpenAIResponse? {
        guard !payload.isEmpty else { return nil }
        let value = payload.joined(separator: "\n")
        payload = []; eventBytes = 0
        if value == "[DONE]" { return nil }
        guard let data = value.data(using: .utf8), let event = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else { throw CommandError.invalid("ChatGPT returned an invalid stream event.") }
        switch type {
        case "response.output_item.done":
            if let index = event["output_index"] as? Int, (0..<100).contains(index), let item = event["item"] as? [String: Any] { items[index] = item }
            return nil
        case "response.content_part.done":
            if let output = event["output_index"] as? Int, (0..<100).contains(output), let content = event["content_index"] as? Int, (0..<100).contains(content), let part = event["part"] as? [String: Any] { parts[output, default: [:]][content] = part }
            return nil
        case "response.output_text.delta", "response.output_text.done", "response.refusal.delta", "response.refusal.done":
            guard let output = event["output_index"] as? Int, (0..<100).contains(output), let content = event["content_index"] as? Int, (0..<100).contains(content) else { return nil }
            let refusal = type.hasPrefix("response.refusal")
            let field = refusal ? "refusal" : "text"
            let existing = parts[output]?[content]?[field] as? String ?? ""
            let value = type.hasSuffix(".delta") ? existing + (event["delta"] as? String ?? "") : event[field] as? String ?? existing
            guard value.utf8.count <= 200_000 else { throw CommandError.invalid("ChatGPT’s answer exceeded the text limit.") }
            parts[output, default: [:]][content] = ["type": refusal ? "refusal" : "output_text", field: value]
            return nil
        case "response.completed":
            guard !completed, var response = event["response"] as? [String: Any], response["status"] as? String == "completed" else { throw ChatGPTPayload.failure(code: nil) }
            // Some account streams omit message bodies from the terminal envelope.
            // Reconstruct from observed content/item events only after completion.
            let terminal = response["output"] as? [[String: Any]] ?? []
            let hasMessage = terminal.contains { item in
                item["type"] as? String == "message" && (item["content"] as? [[String: Any]] ?? []).contains { ["output_text", "refusal"].contains($0["type"] as? String ?? "") }
            }
            if !hasMessage {
                var rebuilt: [[String: Any]] = []
                for index in Set(items.keys).union(parts.keys).sorted() {
                    let item = items[index]
                    if item?["type"] as? String == "message", let content = item?["content"] as? [[String: Any]], !content.isEmpty { rebuilt.append(item!) }
                    else if let content = parts[index], !content.isEmpty { rebuilt.append(["type": "message", "content": content.keys.sorted().compactMap { content[$0] }]) }
                }
                response["output"] = rebuilt
            }
            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: JSONSerialization.data(withJSONObject: response))
            completed = true
            return decoded
        case "response.failed", "response.incomplete", "error":
            let response = event["response"] as? [String: Any]
            let error = (response?["error"] as? [String: Any]) ?? (event["error"] as? [String: Any]) ?? event
            throw ChatGPTPayload.failure(code: error["code"] as? String)
        default: return nil
        }
    }
}

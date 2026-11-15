import Foundation

public struct ServiceWrite {
    public enum Kind: String, CaseIterable, Identifiable {
        case gmailDraft = "Save Gmail draft", gmailSend = "Send Gmail message", drive = "Create Drive text file", calendar = "Create Calendar event", slack = "Post Slack message", notion = "Append to Notion page"
        public var id: String { rawValue }
        public var account: String { self == .slack ? "slack" : self == .notion ? "notion" : "google" }
    }
    public let id: UUID
    public let kind: Kind
    public let target: String
    public let title: String
    public let text: String
    public let start: Date
    public let end: Date
    public init(kind: Kind, target: String, title: String, text: String, start: Date = Date(), end: Date = Date().addingTimeInterval(3600)) {
        id = UUID(); self.kind = kind; self.target = target.trimmingCharacters(in: .whitespacesAndNewlines); self.title = title; self.text = text; self.start = start; self.end = end
    }
    public func request(token: String) throws -> URLRequest {
        guard text.count <= 10000, title.count <= 500, target.count <= 500 else { throw CommandError.invalid("Use up to 10,000 characters of content and a 500-character title or destination.") }
        var endpoint = "", method = "POST", body: [String: Any] = [:]
        var customBody: Data?, contentType = "application/json"
        switch kind {
        case .gmailDraft, .gmailSend:
            guard target.range(of: "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", options: .regularExpression) != nil,
                  !title.contains("\r"), !title.contains("\n"), !text.isEmpty else { throw CommandError.invalid("Enter one explicit email address, a single-line subject and a message.") }
            let message = "To: \(target)\r\nSubject: =?UTF-8?B?\(Data(title.utf8).base64EncodedString())?=\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" + Data(text.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
            let raw = Data(message.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            endpoint = "https://gmail.googleapis.com/gmail/v1/users/me/" + (kind == .gmailDraft ? "drafts" : "messages/send")
            body = kind == .gmailDraft ? ["message": ["raw": raw]] : ["raw": raw]
        case .calendar:
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, start < end, end.timeIntervalSince(start) <= 86400 * 31 else { throw CommandError.invalid("Give the event a title and an end time after its start, within 31 days.") }
            endpoint = "https://www.googleapis.com/calendar/v3/calendars/primary/events?sendUpdates=none"
            body = ["id": "a" + id.uuidString.lowercased().replacingOccurrences(of: "-", with: ""), "summary": title, "description": text, "start": ["dateTime": ISO8601DateFormatter().string(from: start)], "end": ["dateTime": ISO8601DateFormatter().string(from: end)]]
        case .slack:
            guard target.range(of: "^[CG][A-Z0-9]{5,30}$", options: .regularExpression) != nil, !text.isEmpty else { throw CommandError.invalid("Enter an explicit Slack channel ID and message.") }
            endpoint = "https://slack.com/api/chat.postMessage"
            body = ["channel": target, "text": text, "client_msg_id": id.uuidString, "mrkdwn": false, "parse": "none", "link_names": false, "unfurl_links": false, "unfurl_media": false]
        case .notion:
            guard UUID(uuidString: target) != nil, !text.isEmpty else { throw CommandError.invalid("Enter a Notion page UUID and text to append.") }
            endpoint = "https://api.notion.com/v1/blocks/" + target + "/children"; method = "PATCH"
            var remaining = text, children: [[String: Any]] = []
            while !remaining.isEmpty {
                let part = String(remaining.prefix(2000)); remaining = String(remaining.dropFirst(part.count))
                children.append(["object": "block", "type": "paragraph", "paragraph": ["rich_text": [["type": "text", "text": ["content": part]]]]])
            }
            body = ["children": children]
        case .drive:
            guard !title.isEmpty, !text.isEmpty else { throw CommandError.invalid("Give the new text file a name and content.") }
            endpoint = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink"
            let boundary = "newt" + id.uuidString.replacingOccurrences(of: "-", with: "")
            let metadata = try JSONSerialization.data(withJSONObject: ["name": title, "mimeType": "text/plain", "appProperties": ["newtRequest": id.uuidString]])
            var data = Data(("--" + boundary + "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n").utf8); data.append(metadata)
            data.append(Data(("\r\n--" + boundary + "\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n" + text + "\r\n--" + boundary + "--\r\n").utf8))
            customBody = data; contentType = "multipart/related; boundary=" + boundary
        }
        var request = URLRequest(url: URL(string: endpoint)!); request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if kind == .notion { request.setValue("2025-09-03", forHTTPHeaderField: "Notion-Version") }
        request.httpBody = try customBody ?? JSONSerialization.data(withJSONObject: body)
        return request
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Newtv1Core

@MainActor
final class Connections: ObservableObject {
    enum Source: String, CaseIterable, Identifiable {
        case gmail = "Gmail", drive = "Google Drive", calendar = "Google Calendar", slack = "Slack", notion = "Notion"
        var id: String { rawValue }
        var account: String { self == .slack ? "slack" : self == .notion ? "notion" : "google" }
    }
    struct Item: Identifiable { let id: String; let title: String; let subtitle: String; let url: String; let type: String }
    @Published var source: Source = .gmail { didSet { task?.cancel(); items = []; preview = nil; approved = false; message = "Choose Refresh to load this source." } }
    @Published private(set) var items: [Item] = []
    @Published private(set) var preview: BrowserPage?
    @Published var approved = false
    @Published private(set) var busy = false
    @Published var message = "Connect a service, then refresh its list. Nothing is sent to AI automatically."
    @Published private(set) var connected = Set<String>(UserDefaults.standard.stringArray(forKey: "connectedServices") ?? [])
    private let google = GoogleAuthorization()
    private var task: Task<Void,Never>?
    private func saveState() { UserDefaults.standard.set(Array(connected), forKey: "connectedServices") }
    func cancel() { task?.cancel(); google.cancel(); if task == nil { busy = false } }
    func connectGoogle() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.message = "Select the Google Desktop OAuth client JSON downloaded from your own Google Cloud project. It is stored in Keychain."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 64000, let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String:Any], let installed = root["installed"] as? [String:Any], let id = installed["client_id"] as? String, id.hasSuffix(".apps.googleusercontent.com") else { throw Newtv1Failure("Select a Google Desktop OAuth client JSON containing installed.client_id.") }
            let client = GoogleAuthorization.Client(client_id: id, client_secret: installed["client_secret"] as? String)
            busy = true; message = "Complete Google sign-in in your browser. Read-only Gmail, Drive, and Calendar scopes will be requested."
            task = Task { [weak self] in
                guard let self else { return }; defer { self.busy = false; self.task = nil }
                do { let credential = try await self.google.authorize(client); try Task.checkCancellation(); try ServiceSecrets.save(JSONEncoder().encode(credential), account: "google"); self.connected.insert("google"); self.saveState(); self.message = "Google connected. Choose a source and Refresh." }
                catch { self.message = error is CancellationError ? "Google connection cancelled." : error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
    func connectToken(_ token: String, account: String) {
        guard ["slack", "notion"].contains(account), (20...1000).contains(token.count), !token.contains(where: \.isWhitespace) else { message = "Enter a valid integration token."; return }
        do { try ServiceSecrets.save(Data(token.utf8), account: account); connected.insert(account); saveState(); message = "Credential saved in Keychain. Refresh to check its access." }
        catch { message = error.localizedDescription }
    }
    func disconnect(_ account: String) {
        cancel(); ServiceSecrets.remove(account); connected.remove(account); saveState(); items = []; preview = nil; approved = false
        message = "Disconnected locally. You can also revoke the grant in the provider’s account settings."
    }
    private func accessToken(_ account: String) async throws -> String {
        guard let data = try ServiceSecrets.load(account) else { throw Newtv1Failure("Connect this service first.") }
        if account == "google" {
            let credential = try JSONDecoder().decode(GoogleAuthorization.Credential.self, from: data)
            let refreshed = try await google.refresh(credential); try Task.checkCancellation()
            if credential.accessToken != refreshed.accessToken { try ServiceSecrets.save(JSONEncoder().encode(refreshed), account: "google") }
            return refreshed.accessToken
        }
        return String(decoding: data, as: UTF8.self)
    }
    private func json(_ base: String, query: [String:String] = [:], token: String, body: [String:Any]? = nil, notion: Bool = false) async throws -> [String:Any] {
        var url = URLComponents(string: base)!; url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!); request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if notion { request.setValue("2025-09-03", forHTTPHeaderField: "Notion-Version") }
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let data = try await ServiceHTTP().data(request)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw Newtv1Failure("The service returned an unsupported response.") }
        if let ok = value["ok"] as? Bool, !ok { throw Newtv1Failure("Slack denied this request. Check the token's read scopes and channel membership.") }
        return value
    }
    private func safeID(_ id: String) throws -> String {
        guard !id.isEmpty, id.count <= 200, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw Newtv1Failure("Invalid service resource ID.") }; return id
    }
    func refresh() {
        guard !busy else { return }; busy = true; preview = nil; approved = false; items = []
        let source = self.source
        task = Task { [weak self] in
            guard let self else { return }; defer { self.busy = false; self.task = nil }
            do {
                let token = try await self.accessToken(source.account)
                let result: [Item]
                switch source {
                case .gmail:
                    let list = try await self.json("https://gmail.googleapis.com/gmail/v1/users/me/messages", query: ["maxResults": "15", "q": "in:inbox"], token: token)
                    var rows: [Item] = []
                    for message in list["messages"] as? [[String:Any]] ?? [] {
                        try Task.checkCancellation(); let id = try self.safeID(message["id"] as? String ?? "")
                        let metadata = try await self.json("https://gmail.googleapis.com/gmail/v1/users/me/messages/" + id, query: ["format": "metadata"], token: token)
                        let headers = (metadata["payload"] as? [String:Any])?["headers"] as? [[String:Any]] ?? []
                        func header(_ name: String) -> String { headers.first { ($0["name"] as? String)?.lowercased() == name }?["value"] as? String ?? "" }
                        rows.append(Item(id: id, title: header("subject").isEmpty ? "(No subject)" : header("subject"), subtitle: header("from"), url: "https://mail.google.com/mail/u/0/#all/" + id, type: "mail"))
                    }
                    result = rows
                case .drive:
                    let list = try await self.json("https://www.googleapis.com/drive/v3/files", query: ["pageSize": "30", "q": "trashed=false", "orderBy": "modifiedTime desc", "fields": "files(id,name,mimeType,webViewLink,modifiedTime)"], token: token)
                    result = (list["files"] as? [[String:Any]] ?? []).compactMap { file in guard let id = file["id"] as? String else { return nil }; return Item(id: id, title: file["name"] as? String ?? "File", subtitle: file["modifiedTime"] as? String ?? "", url: file["webViewLink"] as? String ?? "https://drive.google.com/file/d/" + id + "/view", type: file["mimeType"] as? String ?? "") }
                case .calendar:
                    let date = ISO8601DateFormatter().string(from: Date())
                    let list = try await self.json("https://www.googleapis.com/calendar/v3/calendars/primary/events", query: ["maxResults": "30", "timeMin": date, "singleEvents": "true", "orderBy": "startTime"], token: token)
                    result = (list["items"] as? [[String:Any]] ?? []).compactMap { event in guard let id = event["id"] as? String else { return nil }; let start = event["start"] as? [String:Any] ?? [:]; return Item(id: id, title: event["summary"] as? String ?? "Event", subtitle: start["dateTime"] as? String ?? start["date"] as? String ?? "", url: event["htmlLink"] as? String ?? "https://calendar.google.com", type: "event") }
                case .slack:
                    let list = try await self.json("https://slack.com/api/conversations.list", query: ["limit": "50", "exclude_archived": "true", "types": "public_channel"], token: token)
                    result = (list["channels"] as? [[String:Any]] ?? []).compactMap { channel in guard let id = channel["id"] as? String else { return nil }; return Item(id: id, title: "#" + (channel["name"] as? String ?? id), subtitle: "Public channel · read scopes and membership apply", url: "https://app.slack.com/client/", type: "channel") }
                case .notion:
                    let list = try await self.json("https://api.notion.com/v1/search", token: token, body: ["filter": ["value": "page", "property": "object"], "page_size": 30, "sort": ["direction": "descending", "timestamp": "last_edited_time"]], notion: true)
                    result = (list["results"] as? [[String:Any]] ?? []).compactMap { page in
                        guard let id = page["id"] as? String else { return nil }
                        let props = page["properties"] as? [String:[String:Any]] ?? [:]
                        let title = props.values.first { $0["type"] as? String == "title" }?["title"] as? [[String:Any]] ?? []
                        let text = title.compactMap { $0["plain_text"] as? String }.joined()
                        return Item(id: id, title: text.isEmpty ? "Untitled page" : text, subtitle: page["last_edited_time"] as? String ?? "", url: page["url"] as? String ?? "https://www.notion.so/" + id.replacingOccurrences(of: "-", with: ""), type: "page")
                    }
                }
                try Task.checkCancellation(); guard self.source == source else { return }
                self.items = result; self.message = result.isEmpty ? "No accessible items were returned." : "Loaded \(result.count) items. Select one to preview locally."
            } catch { if !Task.isCancelled { self.message = error.localizedDescription } }
        }
    }
    func read(_ item: Item) {
        guard !busy else { return }; busy = true; approved = false; preview = nil
        let source = self.source
        task = Task { [weak self] in
            guard let self else { return }; defer { self.busy = false; self.task = nil }
            do {
                let token = try await self.accessToken(source.account); let id = try self.safeID(item.id)
                var text = ""
                switch source {
                case .gmail:
                    let mail = try await self.json("https://gmail.googleapis.com/gmail/v1/users/me/messages/" + id, query: ["format": "full"], token: token)
                    func decode(_ payload: [String:Any], depth: Int = 0) -> String {
                        guard depth < 10 else { return "[Nested content omitted]" }
                        var output = ""
                        if payload["mimeType"] as? String == "text/plain", let encoded = (payload["body"] as? [String:Any])?["data"] as? String {
                            var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); while base64.count % 4 != 0 { base64 += "=" }
                            if let data = Data(base64Encoded: base64) { output += String(decoding: data, as: UTF8.self) }
                        }
                        for part in (payload["parts"] as? [[String:Any]] ?? []).prefix(30) { output += "\n" + decode(part, depth: depth + 1) }
                        return String(output.prefix(30000))
                    }
                    text = decode(mail["payload"] as? [String:Any] ?? [:])
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = mail["snippet"] as? String ?? "No plain-text body is available. Open this message in Gmail for HTML content and attachments." }
                case .drive:
                    guard item.type == "application/vnd.google-apps.document" || item.type == "text/plain" else { throw Newtv1Failure("This viewer supports Google Docs and plain-text files. Open this file in Drive for other formats.") }
                    var url = URLComponents(string: "https://www.googleapis.com/drive/v3/files/" + id + (item.type == "text/plain" ? "" : "/export"))!
                    url.queryItems = [URLQueryItem(name: item.type == "text/plain" ? "alt" : "mimeType", value: item.type == "text/plain" ? "media" : "text/plain")]
                    var request = URLRequest(url: url.url!); request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                    text = String(decoding: try await ServiceHTTP().data(request), as: UTF8.self)
                case .calendar:
                    let event = try await self.json("https://www.googleapis.com/calendar/v3/calendars/primary/events/" + id, token: token)
                    text = [event["summary"] as? String, event["description"] as? String, event["location"] as? String, item.subtitle].compactMap { $0 }.joined(separator: "\n\n")
                case .slack:
                    let messages = try await self.json("https://slack.com/api/conversations.history", query: ["channel": id, "limit": "15"], token: token)
                    text = (messages["messages"] as? [[String:Any]] ?? []).reversed().map { "\($0["user"] as? String ?? "Message") · \($0["ts"] as? String ?? "")\n\($0["text"] as? String ?? "")" }.joined(separator: "\n\n")
                case .notion:
                    let blocks = try await self.json("https://api.notion.com/v1/blocks/" + id + "/children", query: ["page_size": "100"], token: token, notion: true)
                    text = (blocks["results"] as? [[String:Any]] ?? []).map { block in
                        let type = block["type"] as? String ?? ""; let content = block[type] as? [String:Any] ?? [:]
                        let line = (content["rich_text"] as? [[String:Any]] ?? []).compactMap { $0["plain_text"] as? String }.joined()
                        return line + (block["has_children"] as? Bool == true ? " [Nested blocks omitted]" : "")
                    }.joined(separator: "\n")
                    if blocks["has_more"] as? Bool == true { text += "\n[More blocks omitted]" }
                }
                try Task.checkCancellation(); guard self.source == source else { return }
                self.preview = try BrowserPage(title: String(item.title.prefix(500)), url: item.url, text: String(text.prefix(30000))).validated()
                self.message = "Preview is local. Approve one request to ask AI about it. Content is limited to 30,000 characters."
            } catch { if !Task.isCancelled { self.message = error.localizedDescription } }
        }
    }
    func consume() throws -> BrowserPage { guard approved, let preview else { throw Newtv1Failure("Approve this preview for one request first.") }; approved = false; return try preview.validated() }
}

private typealias ConnectionState<T> = SwiftUI.State<T>
struct ConnectionsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var connections: Connections
    @ConnectionState private var token = ""
    @ConnectionState private var question = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your tools, connected.").font(.system(size: 29, weight: .semibold))
            Text("Read Gmail, Drive, Calendar, Slack, and Notion. Credentials stay in Keychain. Lists and previews stay local until you approve one AI question. This release does not send mail/messages or modify service content.").font(.system(size: 12)).foregroundStyle(.gray)
            Picker("Source", selection: $connections.source) { ForEach(Connections.Source.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(connections.busy)
            HStack {
                if connections.source.account == "google" { Button("Connect Google…") { connections.connectGoogle() }.disabled(connections.busy) }
                else { SecureField(connections.source == .slack ? "Slack read-scope token" : "Notion integration token", text: $token).textFieldStyle(.roundedBorder); Button("Save credential") { connections.connectToken(token, account: connections.source.account); token = "" }.disabled(token.isEmpty || connections.busy) }
                Button("Refresh") { connections.refresh() }.disabled(connections.busy)
                if connections.connected.contains(connections.source.account) { Button("Disconnect") { connections.disconnect(connections.source.account) } }
                if connections.busy { ProgressView().controlSize(.small); Button("Cancel") { connections.cancel() } }
            }.buttonStyle(.bordered)
            Text(connections.message).font(.system(size: 12)).foregroundStyle(.gray)
            ForEach(connections.items) { item in
                Button { connections.read(item) } label: { HStack { VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.system(size: 13, weight: .medium)); Text(item.subtitle).font(.system(size: 10)).foregroundStyle(.gray) }; Spacer(); Image(systemName: "doc.text.magnifyingglass") }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).disabled(connections.busy)
            }
            if let preview = connections.preview {
                VStack(alignment: .leading, spacing: 12) {
                    Link("Open in service", destination: URL(string: preview.url)!).font(.system(size: 12))
                    Text(preview.title).font(.system(size: 19, weight: .medium))
                    ScrollView { Text(preview.text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 220)
                    Toggle("Use this content for one OpenAI request", isOn: $connections.approved).toggleStyle(.switch)
                    TextField("Ask about this content…", text: $question).textFieldStyle(.roundedBorder)
                    Button("Ask Newt") { do { let context = try connections.consume(); model.requestBrain(question, mode: .answer, browserPage: context) } catch { connections.message = error.localizedDescription } }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!connections.approved || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.pending != nil || model.capturingScreen)
                }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            DisclosureGroup("Connection setup and access") {
                Text("Google: create a Desktop OAuth client in your Google Cloud project, enable Gmail, Drive and Calendar APIs, and configure its consent screen/test users. Download its client JSON and choose Connect Google. Newtv1 requests read-only scopes for all three sources.\n\nSlack: supply a workspace app token with channels:read and channels:history. Invite the app to channels you want it to read. The viewer lists public channels and loads up to 15 messages; workspace policies/rate limits apply.\n\nNotion: create an internal integration with Read content capability, grant it selected pages, and paste its token. The viewer reads page metadata and top-level blocks.\n\nDisconnect removes the local credential. Revoke provider grants separately in the provider’s settings. Account setup and OAuth verification cannot be completed without your provider accounts.").font(.system(size: 11)).foregroundStyle(.gray).lineSpacing(4)
            }
        }.onChange(of: connections.source) { _ in token = ""; question = "" }
    }
}

import AppKit
import Combine
import Network
import Newtv1Core

private final class ChatGPTHTTP: NSObject, URLSessionTaskDelegate {
    static let shared = ChatGPTHTTP()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func data(_ request: URLRequest, limit: Int = 1_000_000) async throws -> Data {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              ["auth.openai.com", "api.openai.com"].contains(url.host ?? "") else { throw Newtv1Failure("Unsupported ChatGPT endpoint.") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 40
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Newtv1Failure("ChatGPT did not return a response.") }
        var result = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard result.count < limit else { throw Newtv1Failure("ChatGPT response exceeded its size limit.") }
            result.append(byte)
        }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw Newtv1Failure("ChatGPT denied this connection. Reconnect the account and approve plan usage.")
            case 429: throw Newtv1Failure("ChatGPT’s connection or usage limit was reached. Wait and check ChatGPT Settings → Usage.")
            default: throw Newtv1Failure("ChatGPT connection failed (HTTP \(http.statusCode)). Try again when the service is available.")
            }
        }
        return result
    }
    func token(_ fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: ChatGPTAuthorization.issuer + "/api/accounts/oauth/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthFlow.form(fields)
        return try await data(request, limit: 200_000)
    }
    func discovery() async throws -> [String: Any] {
        let data = try await data(URLRequest(url: URL(string: ChatGPTAuthorization.issuer + "/.well-known/openid-configuration")!))
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["issuer"] as? String == ChatGPTAuthorization.issuer else { throw Newtv1Failure("ChatGPT discovery returned an unexpected issuer.") }
        return value
    }
    func discoveredURL(_ value: Any?) throws -> URL {
        guard let raw = value as? String, let url = URL(string: raw), url.scheme == "https", url.host == "auth.openai.com",
              url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.fragment == nil else { throw Newtv1Failure("ChatGPT discovery returned an unsupported endpoint.") }
        return url
    }
}

/// One-use callback receiver bound exclusively to IPv4 loopback. Invalid or unsolicited
/// requests never terminate an otherwise valid sign-in attempt.
@MainActor
private final class ChatGPTCallback {
    private var listener: NWListener?
    private var waiting: CheckedContinuation<(code: String, clientID: String), Error>?
    private var timeout: Task<Void, Never>?
    private var state = ""
    private var previousClientID: String?
    private var port: UInt16 = 0
    private var attempts = 0

    func start(state: String, previousClientID: String?) async throws -> UInt16 {
        self.state = state; self.previousClientID = previousClientID
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let receiver = try NWListener(using: parameters, on: .any)
        listener = receiver
        receiver.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            Self.readHeaders(connection) { data in
                Task { @MainActor [weak self] in self?.receive(data, connection: connection) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { connection.cancel() }
        }
        port = try await withCheckedThrowingContinuation { continuation in
            var resolved = false
            receiver.stateUpdateHandler = { status in Task { @MainActor in
                guard !resolved else { return }
                switch status {
                case .ready: resolved = true; continuation.resume(returning: receiver.port?.rawValue ?? 0)
                case .failed: resolved = true; continuation.resume(throwing: Newtv1Failure("Could not start ChatGPT’s local sign-in callback."))
                case .cancelled: resolved = true; continuation.resume(throwing: CancellationError())
                default: break
                }
            } }
            receiver.start(queue: .global(qos: .userInitiated))
        }
        guard port > 0 else { throw Newtv1Failure("No local sign-in port was allocated.") }
        return port
    }
    func wait(open url: URL) async throws -> (code: String, clientID: String) {
        defer { cancel() }
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiting = continuation
                guard NSWorkspace.shared.open(url) else { cancel(); return }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
                    self?.cancel(error: Newtv1Failure("ChatGPT sign-in timed out. Start a fresh connection."))
                }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
    }
    func cancel(error: Error = CancellationError()) {
        timeout?.cancel(); timeout = nil; listener?.cancel(); listener = nil
        let continuation = waiting; waiting = nil; continuation?.resume(throwing: error)
    }
    private func receive(_ data: Data, connection: NWConnection) {
        attempts += 1
        guard attempts <= 100, let raw = String(data: data, encoding: .utf8), waiting != nil else { connection.cancel(); return }
        let lines = raw.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ").map(String.init) ?? []
        let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        guard first.count == 3, first[0] == "GET", first[2] == "HTTP/1.1", hosts == ["127.0.0.1:\(port)"] else { connection.cancel(); return }
        do {
            let result = try ChatGPTAuthorization.callback(first[1], state: state, previousClientID: previousClientID)
            let body = "Newtv1 received your sign-in. Return to the app while it verifies your account."
            connection.send(content: Data(("HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
            let continuation = waiting; waiting = nil; continuation?.resume(returning: result)
        } catch {
            connection.cancel()
            let items = URLComponents(string: first[1])?.queryItems ?? []
            if items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == state,
               items.contains(where: { $0.name == "error" }) { cancel(error: error) }
        }
    }
    nonisolated private static func readHeaders(_ connection: NWConnection, accumulated: Data = Data(), completion: @escaping (Data) -> Void) {
        guard accumulated.count < 16384 else { connection.cancel(); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384 - accumulated.count) { data, _, ended, error in
            var combined = accumulated; if let data { combined.append(data) }
            if combined.range(of: Data("\r\n\r\n".utf8)) != nil { completion(combined) }
            else if ended || error != nil { connection.cancel() }
            else { readHeaders(connection, accumulated: combined, completion: completion) }
        }
    }
}

@MainActor
final class ChatGPTConnection: ObservableObject {
    static let shared = ChatGPTConnection()
    @Published private(set) var accounts: [ChatGPTRegistration] = []
    @Published private(set) var activeID: String?
    @Published private(set) var models: [ChatGPTModel] = []
    @Published private(set) var busy = false
    @Published private(set) var message = "Continue with ChatGPT to connect an eligible plan."
    @Published var selectedModel: String {
        didSet {
            guard selectedModel != oldValue else { return }
            if let activeID { UserDefaults.standard.set(selectedModel, forKey: "chatGPTModel." + activeID) }
        }
    }
    var active: ChatGPTRegistration? { accounts.first { $0.id == activeID } }
    var connected: Bool { active?.session?.permitsInference == true }
    private var loaded = false
    private var operation: Task<Void, Never>?
    private var refreshTask: (id: String, task: Task<String, Error>)?
    private var receiver: ChatGPTCallback?
    private var generation = UUID()
    private let credentialKey = "chatgpt-plan-accounts-v1"
    private var hostID: String {
        if let value = UserDefaults.standard.string(forKey: "chatGPTAgentHostID"), value.hasPrefix("urn:uuid:"), UUID(uuidString: String(value.dropFirst(9))) != nil { return value }
        let value = "urn:uuid:" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: "chatGPTAgentHostID"); return value
    }
    private init() {
        let savedID = UserDefaults.standard.string(forKey: "chatGPTActiveAccount")
        activeID = savedID
        selectedModel = savedID.flatMap { UserDefaults.standard.string(forKey: "chatGPTModel." + $0) } ?? ""
    }
    func load() throws {
        guard !loaded else { return }
        if let data = try ServiceSecrets.load(credentialKey) {
            guard data.count <= 2_000_000 else { throw Newtv1Failure("Saved ChatGPT accounts exceeded the limit.") }
            let saved = try JSONDecoder().decode([ChatGPTRegistration].self, from: data)
            guard saved.count <= 10, Set(saved.map(\.id)).count == saved.count else { throw Newtv1Failure("Saved ChatGPT accounts are invalid. Reconnect in Settings.") }
            accounts = saved
        }
        loaded = true
        UserDefaults.standard.set(connected, forKey: AIProvider.chatGPT.keyFlag)
        message = connected ? "ChatGPT account connected. Refresh models to choose one available to this account." : "Continue with ChatGPT to connect an eligible plan."
    }
    private func save(_ next: [ChatGPTRegistration]) throws {
        try ServiceSecrets.save(JSONEncoder().encode(next), account: credentialKey)
        accounts = next
        UserDefaults.standard.set(connected, forKey: AIProvider.chatGPT.keyFlag)
    }
    func cancel() {
        generation = UUID(); operation?.cancel(); operation = nil
        receiver?.cancel(); receiver = nil; busy = false
        refreshTask?.task.cancel(); refreshTask = nil
    }
    func select(_ id: String) {
        guard !busy, accounts.contains(where: { $0.id == id }) else { return }
        cancel(); activeID = id; models = []
        UserDefaults.standard.set(id, forKey: "chatGPTActiveAccount")
        selectedModel = UserDefaults.standard.string(forKey: "chatGPTModel." + id) ?? ""
        UserDefaults.standard.set(connected, forKey: AIProvider.chatGPT.keyFlag)
        if connected { refreshModels() } else { message = "This saved account is signed out. Reconnect it to continue." }
    }
    func connect(reconnect: Bool = false) {
        guard !busy else { return }
        do { try load() } catch { message = error.localizedDescription; return }
        guard reconnect || accounts.count < 10 else { message = "Up to ten ChatGPT registrations can be saved."; return }
        let previous = reconnect ? active : nil
        let token = UUID(); generation = token; busy = true; message = "Opening OpenAI sign-in in your browser…"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.receiver?.cancel(); self.busy = false; self.operation = nil; self.receiver = nil } }
            do {
                let state = try OAuthFlow.randomToken(), nonce = try OAuthFlow.randomToken(), verifier = try OAuthFlow.randomToken()
                let receiver = ChatGPTCallback(); self.receiver = receiver
                let port = try await receiver.start(state: state, previousClientID: previous?.clientID)
                let url = try ChatGPTAuthorization.authorizeURL(hostID: self.hostID, port: port, state: state, nonce: nonce, verifier: verifier, registration: previous)
                let callback = try await receiver.wait(open: url)
                let tokenData = try await ChatGPTHTTP.shared.token(["grant_type": "authorization_code", "client_id": callback.clientID,
                    "code": callback.code, "code_verifier": verifier, "redirect_uri": ChatGPTAuthorization.redirectURI(port), "resource": ChatGPTAuthorization.resource])
                let session = try ChatGPTSession.decode(tokenData)
                let discovery = try await ChatGPTHTTP.shared.discovery()
                let keyURL = try ChatGPTHTTP.shared.discoveredURL(discovery["jwks_uri"])
                let keys = try await ChatGPTHTTP.shared.data(URLRequest(url: keyURL))
                let identity = try ChatGPTIdentity.validate(token: session.idToken, jwks: keys, clientID: callback.clientID, nonce: nonce)
                if let previous, previous.subject != identity.subject { throw Newtv1Failure("A different account signed in. Add it as a new account instead of replacing this registration.") }
                try Task.checkCancellation(); guard self.generation == token else { return }
                let registration = ChatGPTRegistration(clientID: callback.clientID, subject: identity.subject, email: identity.email, name: identity.name, session: session)
                var next = self.accounts.filter { $0.id != registration.id }; next.append(registration)
                try self.save(next)
                self.activeID = registration.id; UserDefaults.standard.set(registration.id, forKey: "chatGPTActiveAccount")
                self.models = []; self.selectedModel = UserDefaults.standard.string(forKey: "chatGPTModel." + registration.id) ?? ""
                UserDefaults.standard.set(self.connected, forKey: AIProvider.chatGPT.keyFlag)
                guard session.permitsInference else { self.message = "Signed in, but ChatGPT plan usage was not granted. Reconnect and approve plan usage."; return }
                self.message = "Connected. Loading this account’s models…"
                try await self.fetchModels()
                NSApp.activate(ignoringOtherApps: true)
            } catch { if !Task.isCancelled, self.generation == token { self.message = Self.friendly(error) } }
        }
    }
    func accessToken() async throws -> String {
        try load()
        guard let account = active, let session = account.session, session.permitsInference else { throw Newtv1Failure("Continue with ChatGPT in Settings → AI and approve plan usage.") }
        if session.expiresAt.timeIntervalSinceNow > 90 { return session.accessToken }
        if let pending = refreshTask, pending.id == account.id { return try await pending.task.value }
        guard let refresh = session.refreshToken else { throw Newtv1Failure("Your ChatGPT session expired. Reconnect the saved account.") }
        let token = generation
        let task = Task<String, Error> { [weak self] in
            let data = try await ChatGPTHTTP.shared.token(["grant_type": "refresh_token", "client_id": account.clientID, "refresh_token": refresh, "resource": ChatGPTAuthorization.resource])
            let renewed = try ChatGPTSession.decode(data, previous: session)
            try Task.checkCancellation()
            guard let self, self.generation == token, self.activeID == account.id else { throw CancellationError() }
            guard renewed.permitsInference else { throw Newtv1Failure("ChatGPT plan permission is no longer available. Reconnect this account.") }
            var next = self.accounts
            guard let index = next.firstIndex(where: { $0.id == account.id }) else { throw CancellationError() }
            next[index].session = renewed
            try self.save(next)
            return renewed.accessToken
        }
        refreshTask = (account.id, task)
        defer { if refreshTask?.id == account.id { refreshTask = nil } }
        return try await task.value
    }
    func refreshModels() {
        guard !busy else { return }
        message = "Checking the account connection and loading available models…"
        busy = true; let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.busy = false; self.operation = nil } }
            do { try await self.fetchModels() }
            catch { if !Task.isCancelled { self.message = Self.friendly(error) } }
        }
    }
    private func fetchModels() async throws {
        let id = activeID, token = generation, access = try await accessToken()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
        let catalog = try ChatGPTModel.decode(await ChatGPTHTTP.shared.data(request))
        try Task.checkCancellation(); guard activeID == id, generation == token else { return }
        models = catalog
        if !catalog.contains(where: { $0.id == selectedModel }) { selectedModel = catalog.first?.id ?? "" }
        message = catalog.isEmpty ? "This account returned no available models. Check plan access in ChatGPT Settings." : "Connected · \(catalog.count) available models. Usage counts toward your ChatGPT plan’s app limits."
    }
    func signOut() {
        guard !busy, let account = active else { return }
        cancel(); busy = true; let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            var revoked = account.session?.refreshToken == nil
            do {
                if let refresh = account.session?.refreshToken {
                    let discovery = try await ChatGPTHTTP.shared.discovery()
                    var request = URLRequest(url: try ChatGPTHTTP.shared.discoveredURL(discovery["revocation_endpoint"]))
                    request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    request.httpBody = OAuthFlow.form(["token": refresh, "token_type_hint": "refresh_token", "client_id": account.clientID])
                    _ = try await ChatGPTHTTP.shared.data(request); revoked = true
                }
            } catch { revoked = false }
            guard generation == token else { return }
            defer { busy = false; operation = nil }
            do {
                var next = accounts
                if let i = next.firstIndex(where: { $0.id == account.id }) { next[i].session = nil }
                try save(next); models = []
                message = revoked ? "Signed out. The saved account registration is kept for reconnection." : "Signed out locally. Remote revocation was not confirmed; disconnect Newtv1 in ChatGPT Settings → Usage."
            } catch { message = error.localizedDescription }
        }
    }
    private static func friendly(_ error: Error) -> String {
        if error is CancellationError { return "Connection cancelled." }
        if error is URLError { return "ChatGPT could not be reached. Check your internet connection and try again." }
        return error.localizedDescription
    }
}

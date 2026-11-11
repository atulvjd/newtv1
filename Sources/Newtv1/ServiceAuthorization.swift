import Foundation
import AppKit
import Network
import Security
import Newtv1Core

@MainActor
struct ServiceSecrets {
    private static var cachedCredentials: [String: Data] = [:]

    static func save(_ data: Data, account: String) throws {
        cachedCredentials[account] = nil
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.newtv1.services", kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw Newtv1Failure("Could not save this service credential in Keychain.") }
        } else if status != errSecSuccess { throw Newtv1Failure("Keychain denied the service credential update.") }
        cachedCredentials[account] = data
    }
    static func load(_ account: String) throws -> Data? {
        if let cached = cachedCredentials[account] { return cached }
        var value: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.newtv1.services", kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Newtv1Failure("Keychain access is required for this service. Reconnect it if needed.") }
        guard let data = value as? Data else { throw Newtv1Failure("Keychain returned an unreadable service credential.") }
        cachedCredentials[account] = data
        return data
    }
    static func remove(_ account: String) {
        cachedCredentials[account] = nil
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.newtv1.services", kSecAttrAccount as String: account] as CFDictionary) }
}

final class ServiceHTTP: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func data(_ request: URLRequest) async throws -> Data {
        guard let url = request.url, url.scheme == "https", let host = url.host,
              ["oauth2.googleapis.com", "gmail.googleapis.com", "www.googleapis.com", "slack.com", "api.notion.com"].contains(host) else { throw Newtv1Failure("Unsupported service endpoint.") }
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 40
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil); defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request); try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw Newtv1Failure(code == 401 || code == 403 ? "The service denied access. Check the credential, account permissions, and app scopes, then reconnect." : code == 429 ? "This service is rate limited. Wait before refreshing." : "Service request failed (HTTP \(code)).")
        }
        guard data.count <= 2_000_000 else { throw Newtv1Failure("Service response exceeded the size limit.") }
        return data
    }
}

@MainActor
final class GoogleAuthorization {
    struct Client: Codable { let client_id: String; let client_secret: String? }
    struct Credential: Codable { let client: Client; var accessToken: String; var refreshToken: String; var expiresAt: Date }
    private var listener: NWListener?
    private var waiting: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private var timeout: Task<Void,Never>?
    func cancel() { listener?.cancel(); listener = nil; timeout?.cancel(); timeout = nil; waiting?.resume(throwing: CancellationError()); waiting = nil }
    func authorize(_ client: Client) async throws -> Credential {
        let verifier = try OAuthFlow.randomToken(); expectedState = try OAuthFlow.randomToken()
        let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any); self.listener = listener
        defer { cancel() }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            Self.receiveLine(connection) { line in
                let pieces = line.split(separator: " ")
                Task { @MainActor [weak self] in
                    guard let self, pieces.count == 3, pieces[0] == "GET" else { connection.cancel(); return }
                    do {
                        let code = try OAuthFlow.callback(String(pieces[1]), state: self.expectedState)
                        guard let waiting = self.waiting else { connection.cancel(); return }
                        self.waiting = nil
                        let body = "Newtv1 authorization received. Return to the app."
                        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" + body
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                        waiting.resume(returning: code)
                    } catch {
                        connection.cancel()
                        let query = URLComponents(string: String(pieces[1]))?.queryItems ?? []
                        if query.filter({ $0.name == "state" }).count == 1,
                           query.first(where: { $0.name == "state" })?.value == self.expectedState,
                           query.contains(where: { $0.name == "error" }) {
                            let waiting = self.waiting; self.waiting = nil
                            waiting?.resume(throwing: Newtv1Failure("Google authorization was declined. You can try connecting again."))
                        }
                    }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { connection.cancel() }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            listener.stateUpdateHandler = { state in Task { @MainActor in
                guard !finished else { return }
                switch state {
                case .ready: finished = true; continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): finished = true; continuation.resume(throwing: error)
                case .cancelled: finished = true; continuation.resume(throwing: CancellationError())
                default: break
                }
            } }
            listener.start(queue: .global(qos: .userInitiated))
        }
        guard port > 0 else { throw Newtv1Failure("Could not create a loopback authorization receiver.") }
        let redirect = "http://127.0.0.1:\(port)/oauth"
        let scopes = ["https://www.googleapis.com/auth/gmail.readonly", "https://www.googleapis.com/auth/drive.readonly", "https://www.googleapis.com/auth/calendar.readonly"]
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = ["client_id": client.client_id, "redirect_uri": redirect, "response_type": "code", "scope": scopes.joined(separator: " "), "code_challenge": OAuthFlow.challenge(verifier), "code_challenge_method": "S256", "state": expectedState, "access_type": "offline", "prompt": "consent"].map { URLQueryItem(name: $0.key, value: $0.value) }
        let code: String = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                waiting = continuation
                guard let address = url.url, NSWorkspace.shared.open(address) else { waiting = nil; continuation.resume(throwing: Newtv1Failure("Could not open Google sign-in.")); return }
                timeout = Task { [weak self] in do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }; self?.cancel() }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
        var fields = ["client_id": client.client_id, "grant_type": "authorization_code", "redirect_uri": redirect, "code": code, "code_verifier": verifier]
        if let secret = client.client_secret { fields["client_secret"] = secret }
        let result = try await token(fields)
        guard let access = result["access_token"] as? String, let refresh = result["refresh_token"] as? String else { throw Newtv1Failure("Google returned no offline credential. Remove the old grant and reconnect with consent.") }
        return Credential(client: client, accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval((result["expires_in"] as? Double ?? 3600) - 60))
    }
    nonisolated private static func receiveLine(_ connection: NWConnection, accumulated: Data = Data(), completion: @escaping (String) -> Void) {
        guard accumulated.count < 16384 else { connection.cancel(); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384 - accumulated.count) { data, _, complete, error in
            var buffer = accumulated
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data([13, 10])), let line = String(data: buffer[..<end.lowerBound], encoding: .utf8) { completion(line) }
            else if complete || error != nil { connection.cancel() }
            else { receiveLine(connection, accumulated: buffer, completion: completion) }
        }
    }
    func refresh(_ credential: Credential) async throws -> Credential {
        if credential.expiresAt > Date() { return credential }
        var fields = ["client_id": credential.client.client_id, "grant_type": "refresh_token", "refresh_token": credential.refreshToken]
        if let secret = credential.client.client_secret { fields["client_secret"] = secret }
        let result = try await token(fields)
        guard let access = result["access_token"] as? String else { throw Newtv1Failure("Google's refresh token is no longer valid. Reconnect.") }
        var updated = credential; updated.accessToken = access; updated.expiresAt = Date().addingTimeInterval((result["expires_in"] as? Double ?? 3600) - 60); return updated
    }
    private func token(_ fields: [String:String]) async throws -> [String:Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!); request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = OAuthFlow.form(fields)
        let data = try await ServiceHTTP().data(request)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw Newtv1Failure("Invalid Google token response.") }; return result
    }
}

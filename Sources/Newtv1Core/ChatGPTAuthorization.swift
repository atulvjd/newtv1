import Foundation
import CryptoKit
import Security

public struct ChatGPTRegistration: Codable, Equatable, Identifiable, Sendable {
    public let clientID: String
    public let subject: String
    public let email: String?
    public let name: String?
    public var session: ChatGPTSession?
    public var id: String { SHA256.hash(data: Data((clientID + "\n" + subject).utf8)).map { String(format: "%02x", $0) }.joined() }
    public var label: String { (email ?? name ?? "ChatGPT account") + " · " + String(id.prefix(6)) }
    public init(clientID: String, subject: String, email: String?, name: String?, session: ChatGPTSession?) {
        self.clientID = clientID; self.subject = subject; self.email = email; self.name = name; self.session = session
    }
}

public struct ChatGPTSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String
    public let scopes: Set<String>
    public let expiresAt: Date
    public var permitsInference: Bool { scopes.contains("chatgpt.tokens.use.direct") && scopes.contains("resource.invoke") }
    public init(accessToken: String, refreshToken: String?, idToken: String, scopes: Set<String>, expiresAt: Date) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.idToken = idToken; self.scopes = scopes; self.expiresAt = expiresAt
    }
    public static func decode(_ data: Data, previous: ChatGPTSession? = nil, now: Date = Date()) throws -> ChatGPTSession {
        struct Token: Decodable {
            let access_token: String; let refresh_token: String?; let id_token: String?
            let token_type: String; let scope: String?; let expires_in: Double
        }
        guard data.count <= 200_000 else { throw CommandError.invalid("ChatGPT returned an oversized token response.") }
        let token = try JSONDecoder().decode(Token.self, from: data)
        let id = previous?.idToken ?? token.id_token ?? ""
        let scopes = token.scope.map { Set($0.split(separator: " ").map(String.init)) } ?? previous?.scopes ?? []
        guard token.token_type.lowercased() == "bearer", token.expires_in.isFinite, (1...86400).contains(token.expires_in),
              !token.access_token.isEmpty, token.access_token.count <= 50000, !id.isEmpty, id.count <= 50000,
              token.refresh_token.map({ !$0.isEmpty && $0.count <= 50000 }) ?? true else {
            throw CommandError.invalid("ChatGPT returned an invalid session. Sign in again.")
        }
        return ChatGPTSession(accessToken: token.access_token, refreshToken: token.refresh_token ?? previous?.refreshToken,
            idToken: id, scopes: scopes, expiresAt: now.addingTimeInterval(token.expires_in))
    }
}

public enum ChatGPTAuthorization {
    public static let issuer = "https://auth.openai.com"
    public static let resource = "https://api.openai.com/v1"
    public static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

    public static func authorizeURL(hostID: String, port: UInt16, state: String, nonce: String, verifier: String, registration: ChatGPTRegistration? = nil) throws -> URL {
        guard port > 0, hostID.hasPrefix("urn:uuid:"), UUID(uuidString: String(hostID.dropFirst(9))) != nil,
              [state, nonce, verifier].allSatisfy({ (32...128).contains($0.count) && $0.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) }) }) else { throw CommandError.invalid("Could not prepare a secure ChatGPT sign-in.") }
        var values = ["client_id": registration?.clientID ?? "dynamic_agent_client", "ext_agent_host_id": hostID,
            "redirect_uri": redirectURI(port), "response_type": "code", "scope": scopes, "resource": resource,
            "state": state, "nonce": nonce, "code_challenge_method": "S256", "code_challenge": OAuthFlow.challenge(verifier)]
        if let registration {
            if let idToken = registration.session?.idToken { values["id_token_hint"] = idToken }
            if let email = registration.email { values["login_hint"] = email }
        } else { values["agent_name_hint"] = "Newtv1" }
        var url = URLComponents(string: issuer + "/api/accounts/authorize")!
        url.queryItems = values.keys.sorted().map { URLQueryItem(name: $0, value: values[$0]) }
        guard let result = url.url else { throw CommandError.invalid("Could not create the ChatGPT sign-in URL.") }
        return result
    }

    public static func redirectURI(_ port: UInt16) -> String { "http://127.0.0.1:\(port)/auth/callback" }

    public static func callback(_ target: String, state: String, previousClientID: String?) throws -> (code: String, clientID: String) {
        guard target.count <= 16384, let url = URLComponents(string: target), url.scheme == nil, url.host == nil,
              url.fragment == nil, url.path == "/auth/callback" else { throw CommandError.invalid("Invalid ChatGPT callback.") }
        let items = url.queryItems ?? []
        func single(_ key: String) -> String? {
            let matches = items.filter { $0.name == key }
            return matches.count == 1 ? matches[0].value : nil
        }
        guard let returned = single("state"), secureEqual(returned, state) else { throw CommandError.invalid("ChatGPT sign-in state did not match.") }
        if items.contains(where: { $0.name == "error" }) { throw CommandError.invalid("ChatGPT sign-in was declined. No account was changed.") }
        guard items.filter({ $0.name == "client_id" }).count <= 1,
              let code = single("code"), !code.isEmpty, code.count <= 8192,
              let client = single("client_id") ?? previousClientID, !client.isEmpty, client != "dynamic_agent_client", client.count <= 512,
              !client.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              previousClientID == nil || client == previousClientID else { throw CommandError.invalid("ChatGPT returned an incomplete or mismatched account registration.") }
        return (code, client)
    }

    public static func secureEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

public struct ChatGPTIdentity: Equatable {
    public let subject: String
    public let email: String?
    public let name: String?

    public static func validate(token: String, jwks: Data, clientID: String, nonce: String, now: Date = Date()) throws -> ChatGPTIdentity {
        func invalid() -> CommandError { .invalid("ChatGPT identity validation failed. Please start a fresh sign-in.") }
        guard token.count <= 50000, jwks.count <= 1_000_000 else { throw invalid() }
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 3, let headerData = decodeURL(pieces[0]), let claimsData = decodeURL(pieces[1]), let signature = decodeURL(pieces[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "RS256", header["crit"] == nil,
              let kid = header["kid"] as? String, !kid.isEmpty, kid.count <= 256,
              let keyset = try JSONSerialization.jsonObject(with: jwks) as? [String: Any], let keys = keyset["keys"] as? [[String: Any]], keys.count <= 100 else { throw invalid() }
        let matches = keys.filter { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" && ($0["alg"] == nil || $0["alg"] as? String == "RS256") && ($0["use"] == nil || $0["use"] as? String == "sig") }
        guard matches.count == 1, let key = matches.first, let n = key["n"] as? String, let e = key["e"] as? String,
              let modulus = decodeURL(n), let exponent = decodeURL(e), (256...1024).contains(modulus.count), (1...8).contains(exponent.count), exponent.contains(where: { $0 != 0 }) else { throw invalid() }
        let der = sequence(integer(modulus) + integer(exponent))
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let publicKey = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data((pieces[0] + "." + pieces[1]).utf8) as CFData, signature as CFData, nil),
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any], claims["iss"] as? String == ChatGPTAuthorization.issuer,
              let sub = claims["sub"] as? String, !sub.isEmpty, sub.count <= 512,
              let returnedNonce = claims["nonce"] as? String, ChatGPTAuthorization.secureEqual(returnedNonce, nonce),
              let exp = claims["exp"] as? Double, exp.isFinite, exp > now.timeIntervalSince1970 else { throw invalid() }
        let audiences = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard audiences.contains(clientID), (audiences.count <= 1 || claims["azp"] as? String == clientID),
              claims["azp"] == nil || claims["azp"] as? String == clientID,
              (claims["iat"] as? Double).map({ $0.isFinite && $0 <= now.timeIntervalSince1970 + 60 }) ?? true,
              (claims["nbf"] as? Double).map({ $0.isFinite && $0 <= now.timeIntervalSince1970 + 60 }) ?? true else { throw invalid() }
        return ChatGPTIdentity(subject: sub, email: (claims["email"] as? String).map { String($0.prefix(320)) }, name: (claims["name"] as? String).map { String($0.prefix(160)) })
    }
    private static func decodeURL(_ value: String) -> Data? {
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }) else { return nil }
        let base = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base + String(repeating: "=", count: (4 - base.count % 4) % 4))
    }
    private static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var number = count, bytes: [UInt8] = []
        while number > 0 { bytes.insert(UInt8(number & 255), at: 0); number >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    private static func integer(_ bytes: Data) -> Data {
        var value = Data(bytes.drop(while: { $0 == 0 }))
        if value.isEmpty { value = Data([0]) }
        if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
        return Data([0x02]) + length(value.count) + value
    }
    private static func sequence(_ data: Data) -> Data { Data([0x30]) + length(data.count) + data }
}

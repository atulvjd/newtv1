import Foundation
import CryptoKit
import Security

public enum OAuthFlow {
    public static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CommandError.invalid("Could not generate OAuth state.") }
        return base64URL(Data(bytes))
    }
    public static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    private static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    public static func form(_ values: [String: String]) -> Data {
        var parts = URLComponents(); parts.queryItems = values.keys.sorted().map { URLQueryItem(name: $0, value: values[$0]) }
        return Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    public static func callback(_ target: String, state: String) throws -> String {
        guard target.count <= 8192, target.hasPrefix("/oauth?"), let parts = URLComponents(string: target), parts.path == "/oauth", parts.scheme == nil, parts.host == nil else { throw CommandError.invalid("Invalid OAuth callback.") }
        let items = parts.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == state else { throw CommandError.invalid("OAuth state did not match.") }
        guard !items.contains(where: { $0.name == "error" }), items.filter({ $0.name == "code" }).count == 1, let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.count <= 4096 else { throw CommandError.invalid("Authorization was declined or returned no code.") }
        return code
    }
}

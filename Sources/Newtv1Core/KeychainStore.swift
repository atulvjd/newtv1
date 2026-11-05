import Foundation
import Security

public enum KeychainStore {
    private static let service = "dev.newtv1.mac.openai"
    private static let account = "api-key"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }

    public static func save(_ raw: String, trustedApp: String? = nil) throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20, !key.contains(where: \.isWhitespace) else { throw CommandError.invalid("Enter a valid OpenAI API key.") }
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Newtv1 OpenAI API key"
        if let path = trustedApp {
            var application: SecTrustedApplication?
            guard SecTrustedApplicationCreateFromPath(path, &application) == errSecSuccess, let application else { throw CommandError.invalid("Cannot set up Keychain access for Newtv1.") }
            var access: SecAccess?
            guard SecAccessCreate("Newtv1 OpenAI API key" as CFString, [application] as CFArray, &access) == errSecSuccess, let access else { throw CommandError.invalid("Cannot create Keychain access rules.") }
            item[kSecAttrAccess as String] = access
        }
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            var updates: [String: Any] = [kSecValueData as String: Data(key.utf8)]
            if let access = item[kSecAttrAccess as String] { updates[kSecAttrAccess as String] = access }
            try check(SecItemUpdate(query as CFDictionary, updates as CFDictionary))
        } else { try check(status) }
    }

    public static func load() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw CommandError.invalid("Keychain returned an unreadable key.") }
        return String(data: data, encoding: .utf8)
    }

    public static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw CommandError.invalid("Keychain access failed (\(status)). Unlock your login Keychain and try again.") }
    }
}

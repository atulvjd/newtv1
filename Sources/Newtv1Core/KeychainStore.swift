import Foundation
import Security

public enum KeychainStore {
    private static let cacheLock = NSRecursiveLock()
    private static var cachedKeys: [String: String] = [:]

    private static func cachedKey(_ provider: AIProvider) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedKeys[provider.rawValue]
    }

    private static func cache(_ key: String?, provider: AIProvider) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedKeys[provider.rawValue] = key
    }

    private static let account = "api-key"
    private static func query(_ provider: AIProvider) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.newtv1.mac." + provider.rawValue, kSecAttrAccount as String: account] }

    public static func save(_ raw: String, trustedApp: String? = nil, provider: AIProvider = .openAI) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20, key.count <= 1024, !key.contains(where: \.isWhitespace), provider == .gemini || key.hasPrefix("sk-") else { throw CommandError.invalid("Enter a valid " + provider.title + " API key.") }
        cache(nil, provider: provider)
        var item = query(provider)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Newtv1 " + provider.title + " API key"
        if let path = trustedApp {
            var application: SecTrustedApplication?
            guard SecTrustedApplicationCreateFromPath(path, &application) == errSecSuccess, let application else { throw CommandError.invalid("Cannot set up Keychain access for Newtv1.") }
            var access: SecAccess?
            guard SecAccessCreate("Newtv1 " + provider.title + " API key" as CFString, [application] as CFArray, &access) == errSecSuccess, let access else { throw CommandError.invalid("Cannot create Keychain access rules.") }
            item[kSecAttrAccess as String] = access
        }
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            var updates: [String: Any] = [kSecValueData as String: Data(key.utf8)]
            if let access = item[kSecAttrAccess as String] { updates[kSecAttrAccess as String] = access }
            try check(SecItemUpdate(query(provider) as CFDictionary, updates as CFDictionary))
        } else { try check(status) }
        cache(key, provider: provider)
    }

    public static func load(provider: AIProvider = .openAI) throws -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedKey(provider) { return cached }
        var lookup = query(provider)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw CommandError.invalid("Keychain returned an unreadable key.") }
        guard let key = String(data: data, encoding: .utf8) else {
            throw CommandError.invalid("Keychain returned an unreadable key.")
        }
        cache(key, provider: provider)
        return key
    }

    public static func remove(provider: AIProvider = .openAI) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache(nil, provider: provider)
        let status = SecItemDelete(query(provider) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            if status == errSecAuthFailed { throw CommandError.invalid("macOS denied this Newtv1 build access to the saved API key. Allow it in the Keychain prompt, or update the Newtv1 key's access in Keychain Access. Rebuilding a locally signed app can require approval again.") }
            throw CommandError.invalid("Keychain access failed (\(status)). Unlock your login Keychain and try again.")
        }
    }
}

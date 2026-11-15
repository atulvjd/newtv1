import Foundation

public struct BrowserBridgeState: Codable {
    public let session: UUID
    public let updatedAt: Date
    public let connected: Bool
    public let message: String
    public let snapshot: BrowserSnapshot?
    public let result: BrowserActionResult?
    public init(session: UUID, updatedAt: Date, connected: Bool, message: String, snapshot: BrowserSnapshot?, result: BrowserActionResult?) {
        self.session = session; self.updatedAt = updatedAt; self.connected = connected; self.message = message; self.snapshot = snapshot; self.result = result
    }
    public var live: Bool { connected && Date().timeIntervalSince(updatedAt) < 6 }
}

/// Owner-only IPC shared by the app and the native host; no network listener.
public enum BrowserBridge {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Newtv1/BrowserBridge", isDirectory: true)
    }
    public static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    public static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    public static func read<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = directory.appendingPathComponent(name)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 200_000 else { throw CommandError.invalid("Invalid browser bridge file.") }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }
    public static func write<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try encoder.encode(value)
        guard data.count <= 200_000 else { throw CommandError.invalid("Browser message exceeds limits.") }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func clearCommand() { try? FileManager.default.removeItem(at: directory.appendingPathComponent("command.json")) }
}

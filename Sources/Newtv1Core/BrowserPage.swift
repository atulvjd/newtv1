import Foundation

public struct BrowserPage: Codable, Equatable {
    public let version: Int
    public let title: String
    public let url: String
    public let text: String
    public let capturedAt: Date
    public init(version: Int = 1, title: String, url: String, text: String, capturedAt: Date = Date()) {
        self.version = version; self.title = title; self.url = url; self.text = text; self.capturedAt = capturedAt
    }
    public func validated(now: Date = Date()) throws -> Self {
        guard version == 1, title.count <= 500, url.count <= 4000, text.count <= 30000,
              let address = URL(string: url), ["https", "http"].contains(address.scheme?.lowercased() ?? ""), address.host != nil,
              address.user == nil, address.password == nil,
              capturedAt <= now.addingTimeInterval(60), now.timeIntervalSince(capturedAt) <= 900 else {
            throw CommandError.invalid("Browser context is invalid or older than 15 minutes. Capture the page again.")
        }
        return self
    }
    public static func decode(_ data: Data, now: Date = Date()) throws -> Self {
        guard data.count <= 200_000 else { throw CommandError.invalid("Browser context is too large.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data).validated(now: now)
    }
}

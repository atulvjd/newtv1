import Foundation

/// A short-lived grant for one user-selected file, one document and one reviewed command.
public struct BrowserUpload: Codable {
    public static let maximumSize = 20 * 1024 * 1024
    public static let chunkSize = 64 * 1024
    public let commandID: UUID
    public let session: UUID
    public let document: UUID
    public let fileName: String
    public let mimeType: String
    public let size: Int
    public let expiresAt: Date
    public init(command: BrowserCommand, fileName: String, size: Int, mimeType: String = "application/octet-stream", now: Date = Date()) throws {
        guard command.action.kind == .upload, !fileName.isEmpty, fileName.count <= 255,
              !fileName.contains("/"), !fileName.contains("\\"), (0...Self.maximumSize).contains(size),
              mimeType.count <= 100, mimeType.contains("/"), mimeType.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/-.+".contains($0)) }) else { throw CommandError.invalid("Choose one file up to 20 MB.") }
        commandID = command.id; session = command.session; document = command.document
        self.fileName = fileName; self.mimeType = mimeType; self.size = size; expiresAt = now.addingTimeInterval(120)
    }
    public func range(index: Int, session: UUID, document: UUID, now: Date = Date()) throws -> Range<Int> {
        guard session == self.session, document == self.document, expiresAt > now,
              index >= 0, index <= Self.maximumSize / Self.chunkSize else { throw CommandError.invalid("Upload grant expired or does not match this document.") }
        let start = index * Self.chunkSize
        guard start < size || (size == 0 && index == 0) else { throw CommandError.invalid("Invalid upload chunk.") }
        return start..<min(size, start + Self.chunkSize)
    }
}

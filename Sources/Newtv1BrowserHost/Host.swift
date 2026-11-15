import Foundation
import Newtv1Core

// The extension starts a port only after the user connects one active tab.
@main
struct BrowserHost {
    static func main() {
        do {
            let input = FileHandle.standardInput
            func readExactly(_ size: Int) throws -> Data {
                var data = Data()
                while data.count < size {
                    guard let chunk = try input.read(upToCount: size - data.count), !chunk.isEmpty else { throw CommandError.invalid("Incomplete browser message.") }
                    data.append(chunk)
                }
                return data
            }
            while true {
            guard let first = try input.read(upToCount: 1), !first.isEmpty else { return }
            var header = first; header.append(try readExactly(3))
            let size = header.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            guard size > 0, size <= 200_000 else { throw CommandError.invalid("Browser message exceeds limits.") }
            let data = try readExactly(size)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["kind"] as? String == "uploadChunk" {
                let request = try BrowserBridge.decoder.decode(UploadRequest.self, from: data)
                let id = request.commandID.uuidString
                let grant = try BrowserBridge.read("upload-" + id + ".json", as: BrowserUpload.self)
                guard grant.commandID == request.commandID else { throw CommandError.invalid("Invalid upload grant.") }
                let range = try grant.range(index: request.index, session: request.session, document: request.document)
                let url = BrowserBridge.directory.appendingPathComponent("upload-" + id + ".data")
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      (attributes[.size] as? NSNumber)?.intValue == grant.size else { throw CommandError.invalid("The staged upload changed.") }
                let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                try file.seek(toOffset: UInt64(range.lowerBound))
                let chunk = try file.read(upToCount: range.count) ?? Data()
                guard chunk.count == range.count else { throw CommandError.invalid("Incomplete upload chunk.") }
                if range.upperBound == grant.size {
                    try? FileManager.default.removeItem(at: url)
                    try? FileManager.default.removeItem(at: BrowserBridge.directory.appendingPathComponent("upload-" + id + ".json"))
                }
                respond(["ok": true, "chunk": ["commandID": id, "index": request.index, "fileName": grant.fileName, "mimeType": grant.mimeType, "size": grant.size, "data": chunk.base64EncodedString(), "last": range.upperBound == grant.size]])
                continue
            }
            if object?["kind"] as? String == "poll" {
                let poll = try BrowserBridge.decoder.decode(Poll.self, from: data)
                guard poll.message.count <= 1000 else { throw CommandError.invalid("Invalid browser status.") }
                if let snapshot = poll.snapshot { _ = try snapshot.validated(); guard snapshot.session == poll.session else { throw CommandError.invalid("Browser session mismatch.") } }
                if let result = poll.result { guard result.message.count <= 2000 else { throw CommandError.invalid("Invalid action result.") }; if let snapshot = result.snapshot { _ = try snapshot.validated(); guard snapshot.session == poll.session else { throw CommandError.invalid("Result session mismatch.") } } }
                let previous = try? BrowserBridge.read("state.json", as: BrowserBridgeState.self)
                let state = BrowserBridgeState(session: poll.session, updatedAt: Date(), connected: poll.connected, message: poll.message,
                    snapshot: poll.snapshot, result: poll.result ?? (previous?.session == poll.session ? previous?.result : nil))
                try BrowserBridge.write(state, to: "state.json")
                if poll.connected, let snapshot = poll.snapshot, let command = try? BrowserBridge.read("command.json", as: BrowserCommand.self), command.session == poll.session {
                    BrowserBridge.clearCommand() // Claim once; never replay a possibly completed mutation.
                    if (try? command.validated(for: snapshot)) != nil {
                        respondData(try BrowserBridge.encoder.encode(CommandReply(ok: true, command: command)))
                    } else {
                        respond(["ok": true])
                    }
                } else { respond(["ok": true]) }
                continue
            }
            let page = try BrowserPage.decode(data)
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Newtv1/BrowserInbox", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let destination = directory.appendingPathComponent("page.json")
            try encoder.encode(page).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            respond(["ok": true, "message": "Saved locally. Open Newtv1 → Browser to review and use this page."])
            }
        } catch { respond(["ok": false, "message": error.localizedDescription]) }
    }
    private struct Poll: Decodable {
        let session: UUID
        let connected: Bool
        let message: String
        let snapshot: BrowserSnapshot?
        let result: BrowserActionResult?
    }
    private struct CommandReply: Encodable { let ok: Bool; let command: BrowserCommand }
    private struct UploadRequest: Decodable { let commandID: UUID; let session: UUID; let document: UUID; let index: Int }
    private static func respond(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        respondData(data)
    }
    private static func respondData(_ data: Data) {
        let size = UInt32(data.count)
        var packet = Data((0..<4).map { UInt8((size >> ($0 * 8)) & 255) }); packet.append(data)
        try? FileHandle.standardOutput.write(contentsOf: packet)
    }
}

import Foundation
import Newtv1Core

// Native messaging runs only after an explicit extension button press.
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
            let header = try readExactly(4)
            let size = header.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            guard size > 0, size <= 200_000 else { throw CommandError.invalid("Browser message exceeds limits.") }
            let data = try readExactly(size)
            let page = try BrowserPage.decode(data)
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Newtv1/BrowserInbox", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let destination = directory.appendingPathComponent("page.json")
            try encoder.encode(page).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            respond(["ok": true, "message": "Saved locally. Open Newtv1 → Browser to review and use this page."])
        } catch { respond(["ok": false, "message": error.localizedDescription]) }
    }
    private static func respond(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        let size = UInt32(data.count)
        var packet = Data((0..<4).map { UInt8((size >> ($0 * 8)) & 255) }); packet.append(data)
        try? FileHandle.standardOutput.write(contentsOf: packet)
    }
}

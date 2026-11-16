import Foundation
import Newtv1Core

// A single bounded image over stdin; a single JSON response over stdout. No capture,
// credentials, network, or temporary image files. A Vision failure stays in this process.
do {
    var data = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount: 65536), !chunk.isEmpty {
        data.append(chunk)
        guard data.count <= 5_000_000 else { throw CommandError.invalid("Image exceeds 5 MB.") }
    }
    let text = try ScreenTextRecognition.read(data)
    try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: ["text": text]))
} catch {
    try? FileHandle.standardError.write(contentsOf: Data("Local screen text recognition failed.\n".utf8))
    exit(1)
}

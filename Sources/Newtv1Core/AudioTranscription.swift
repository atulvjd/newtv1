import Foundation

public enum AudioTranscription {
    public static func multipart(wav: Data, boundary: String) throws -> Data {
        guard (44...2_000_000).contains(wav.count), String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF", String(decoding: wav.dropFirst(8).prefix(4), as: UTF8.self) == "WAVE", boundary.count <= 100, !boundary.isEmpty, boundary.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { throw CommandError.invalid("A valid WAV recording under 2 MB is required.") }
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-mini-transcribe\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"utterance.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body.append(wav); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); return body
    }
    public static func text(from data: Data) throws -> String {
        struct Response: Decodable { let text: String }
        guard data.count <= 200_000 else { throw CommandError.invalid("Transcription response is too large.") }
        let text = try JSONDecoder().decode(Response.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 16000 else { throw CommandError.invalid("Transcription is too long.") }
        return text
    }
}

import Foundation

public struct AudioDeviceIdentity: Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum AudioDeviceMatch {
    public static func resolve(_ query: String, devices: [AudioDeviceIdentity]) throws -> String {
        // UI selections use the exact stable UID. Spoken names must match exactly and uniquely.
        if let device = devices.first(where: { $0.id == query }) { return device.id }
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let key = normalized(query)
        let matches = devices.filter { normalized($0.name) == key }
        guard !key.isEmpty, matches.count == 1, let match = matches.first else {
            throw CommandError.invalid(matches.count > 1 ? "More than one audio device has that name. Choose it in System Controls." : "No exact audio device match. Use the name shown in System Controls.")
        }
        return match.id
    }
}

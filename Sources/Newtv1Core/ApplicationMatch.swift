import Foundation

public struct InstalledApplication: Equatable, Sendable {
    public let name: String
    public let bundleID: String
    public let path: String

    public init(name: String, bundleID: String, path: String) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
    }
}

public enum ApplicationMatch {
    private static let aliases: [String: [String]] = [
        "vscode": ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
        "vs code": ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
        "visual studio code": ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
        "code": ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
        "insider": ["com.microsoft.VSCodeInsiders"],
        "insiders": ["com.microsoft.VSCodeInsiders"],
        "code insiders": ["com.microsoft.VSCodeInsiders"],
        "vs code insiders": ["com.microsoft.VSCodeInsiders"],
        "brave": ["com.brave.Browser"],
        "chrome": ["com.google.Chrome"],
        "settings": ["com.apple.systempreferences"],
        "system preferences": ["com.apple.systempreferences"]
    ]

    private static func normalized(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasSuffix(".app") { value = String(value.dropLast(4)) }
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    public static func resolve(_ name: String, in applications: [InstalledApplication]) throws -> InstalledApplication {
        let key = normalized(name)
        guard !key.isEmpty else { throw CommandError.invalid("Specify an application name.") }
        // Exact paths and bundle IDs disambiguate apps with the same display name.
        let explicit = applications.filter { $0.path == name || $0.bundleID.lowercased() == name.lowercased() }
        if explicit.count == 1 { return explicit[0] }
        if explicit.count > 1 { throw ambiguity(name, explicit) }
        let exact = applications.filter { normalized($0.name) == key || normalized(URL(fileURLWithPath: $0.path).lastPathComponent) == key }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 { throw ambiguity(name, exact) }
        if let identifiers = aliases[key] {
            for identifier in identifiers {
                let matches = applications.filter { $0.bundleID == identifier }
                if matches.count == 1 { return matches[0] }
                if matches.count > 1 { throw ambiguity(name, matches) }
            }
        }
        let words = key.split(separator: " ")
        let matches = applications.filter { app in
            let tokens = normalized(app.name).split(separator: " ")
            return words.allSatisfy { tokens.contains($0) }
        }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 { throw ambiguity(name, matches) }
        throw CommandError.unknown(name)
    }

    private static func ambiguity(_ name: String, _ matches: [InstalledApplication]) -> CommandError {
        let choices = matches.prefix(5).map { $0.name + " (" + $0.path + ")" }.joined(separator: ", ")
        return .invalid("More than one app matches “" + name + "”. Use its exact name or path. Matches: " + choices)
    }
}

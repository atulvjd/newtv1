import Foundation

public struct BrowserControl: Codable, Equatable, Identifiable {
    public let id: Int
    public let role: String
    public let label: String
    public let editable: Bool
    public let options: [String]?
    public init(id: Int, role: String, label: String, editable: Bool, options: [String]? = nil) {
        self.id = id; self.role = role; self.label = label; self.editable = editable
        self.options = options
    }
}

public struct BrowserSnapshot: Codable, Equatable {
    public let session: UUID
    public let document: UUID
    public let revision: Int
    public let page: BrowserPage
    public let controls: [BrowserControl]
    public init(session: UUID, document: UUID, revision: Int, page: BrowserPage, controls: [BrowserControl]) {
        self.session = session; self.document = document; self.revision = revision; self.page = page; self.controls = controls
    }
    public func validated(now: Date = Date()) throws -> Self {
        _ = try page.validated(now: now)
        guard revision >= 0, revision < Int.max, controls.count <= 160,
              Set(controls.map(\.id)).count == controls.count,
              controls.allSatisfy({ $0.id > 0 && $0.id <= 160 && $0.label.count <= 200 && $0.role.count <= 40 && ($0.options ?? []).count <= 50 && ($0.options ?? []).allSatisfy { $0.count <= 100 } }) else {
            throw CommandError.invalid("Invalid browser control snapshot.")
        }
        return self
    }
}

public struct BrowserAction: Codable, Equatable {
    public enum Kind: String, Codable, CaseIterable { case click, type, select, scroll, back, observe, upload }
    public let kind: Kind
    public let target: Int
    public let value: String
    public init(kind: Kind, target: Int = 0, value: String = "") { self.kind = kind; self.target = target; self.value = value }
    public func validated(in snapshot: BrowserSnapshot) throws -> Self {
        _ = try snapshot.validated()
        guard value.count <= 8000 else { throw CommandError.invalid("Browser input exceeds 8,000 characters.") }
        switch kind {
        case .click, .type, .select, .upload:
            guard let control = snapshot.controls.first(where: { $0.id == target }),
                  kind != .type || control.editable,
                  kind != .select || (control.role == "select" && (control.options ?? []).contains(value)),
                  kind != .upload || (control.role == "file" && value.isEmpty),
                  control.role != "file" || kind == .upload else { throw CommandError.invalid("That browser control is unavailable. Observe the page again.") }
        case .scroll:
            guard ["up", "down"].contains(value), target == 0 else { throw CommandError.invalid("Invalid browser scroll direction.") }
        case .back, .observe:
            guard target == 0, value.isEmpty else { throw CommandError.invalid("Unexpected browser action arguments.") }
        }
        return self
    }
    public func summary(in snapshot: BrowserSnapshot) -> String {
        let label = snapshot.controls.first(where: { $0.id == target })?.label ?? "control \(target)"
        switch kind {
        case .click: return "Click “\(label)”"
        case .type: return "Replace text in “\(label)” with “\(value)”"
        case .select: return "Select “\(value)” in “\(label)”"
        case .scroll: return "Scroll \(value) one page"
        case .back: return "Go back in the connected tab"
        case .observe: return "Observe the connected page again"
        case .upload: return "Attach a file you choose to “\(label)”"
        }
    }
}

public struct BrowserCommand: Codable, Equatable, Identifiable {
    public let id: UUID
    public let session: UUID
    public let document: UUID
    public let revision: Int
    public let expiresAt: Date
    public let action: BrowserAction
    public init(snapshot: BrowserSnapshot, action: BrowserAction, now: Date = Date()) throws {
        self.action = try action.validated(in: snapshot)
        id = UUID(); session = snapshot.session; document = snapshot.document; revision = snapshot.revision
        // Native messaging uses whole-second ISO8601 dates in both Swift and JavaScript.
        expiresAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970) + 20)
    }
    public func validated(for snapshot: BrowserSnapshot, now: Date = Date()) throws -> Self {
        guard session == snapshot.session, document == snapshot.document, revision == snapshot.revision,
              expiresAt > now, expiresAt <= now.addingTimeInterval(21) else {
            throw CommandError.invalid("The browser changed or this action expired. Observe and review again.")
        }
        _ = try action.validated(in: snapshot)
        return self
    }
}

public struct BrowserActionResult: Codable {
    public let id: UUID
    public let ok: Bool
    public let message: String
    public let snapshot: BrowserSnapshot?
}

public struct BrowserStep: Codable {
    public let status: String
    public let explanation: String
    public let kind: String
    public let target: Int
    public let value: String
    public func action(in snapshot: BrowserSnapshot) throws -> BrowserAction? {
        guard ["action", "done", "blocked"].contains(status), !explanation.isEmpty, explanation.count <= 8000 else { throw CommandError.invalid("Invalid browser task response.") }
        guard status == "action" else { return nil }
        guard let kind = BrowserAction.Kind(rawValue: kind) else { throw CommandError.invalid("Unsupported browser action.") }
        return try BrowserAction(kind: kind, target: target, value: value).validated(in: snapshot)
    }
}

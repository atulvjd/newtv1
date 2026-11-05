import AppKit
import ApplicationServices
import Carbon
import VoxCore

struct VoxFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func stop() {
        lock.lock(); cancelled = true; let running = process; lock.unlock()
        guard let running, running.isRunning else { return }
        running.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if running.isRunning { kill(running.processIdentifier, SIGKILL) }
        }
    }
    func run(_ path: String, _ arguments: [String], timeout: Double = 30) async throws -> String {
        reset()
        try Task.checkCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let task = Process()
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: output.path, contents: nil)
                do {
                    let handle = try FileHandle(forWritingTo: output)
                    task.executableURL = URL(fileURLWithPath: path)
                    task.arguments = arguments
                    task.standardOutput = handle; task.standardError = handle
                    task.standardInput = FileHandle.nullDevice
                    task.terminationHandler = { process in
                        try? handle.close()
                        defer { try? FileManager.default.removeItem(at: output) }
                        let reader = try? FileHandle(forReadingFrom: output)
                        let data = (try? reader?.read(upToCount: 16_384)) ?? Data()
                        try? reader?.close()
                        let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        if process.terminationStatus == 0 { continuation.resume(returning: result) }
                        else { continuation.resume(throwing: VoxFailure(result.isEmpty ? "Command stopped or failed (\(process.terminationStatus))." : result)) }
                    }
                    try self.launch(task)
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if task.isRunning {
                            task.terminate()
                            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                            }
                        }
                    }
                } catch {
                    try? FileManager.default.removeItem(at: output)
                    continuation.resume(throwing: error)
                }
            }
        }, onCancel: { self.stop() })
    }
    private func reset() {
        lock.lock(); defer { lock.unlock() }
        cancelled = false; process = nil
    }
    private func launch(_ task: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        process = task
        try task.run()
    }
}

struct ControlTarget: Identifiable {
    let id: Int
    let label: String
    let element: AXUIElement
    let frame: CGRect
}

@MainActor
final class Automation {
    var targetApp: NSRunningApplication?
    private(set) var targets: [ControlTarget] = []
    private var numberedPID: pid_t?
    private var overlays: [NSPanel] = []
    let runner = ProcessRunner()
    var trusted: Bool { AXIsProcessTrusted() }

    func externalAppActivated(_ app: NSRunningApplication) {
        if let numberedPID, numberedPID != app.processIdentifier { hideNumbers() }
    }

    func requireAccessibility() throws {
        guard trusted else { throw VoxFailure("Enable Vox in System Settings → Privacy & Security → Accessibility, then try again.") }
    }

    func focusTarget() async throws {
        guard let targetApp, !targetApp.isTerminated, targetApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw VoxFailure("Switch to the app you want to control first, then use Option–Space to speak.")
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != targetApp.processIdentifier {
            targetApp.activate(options: [.activateIgnoringOtherApps])
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
            throw VoxFailure("Could not focus \(targetApp.localizedName ?? "the target app").")
        }
    }

    func execute(_ action: Action) async throws -> String {
        try Task.checkCancellation()
        switch action {
        case .openApp(let name):
            _ = try await runner.run("/usr/bin/open", ["-a", name])
            try await Task.sleep(nanoseconds: 500_000_000)
            if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { targetApp = front }
        case .quitApp(let name):
            let matches = NSWorkspace.shared.runningApplications.filter { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame }
            guard matches.count == 1, let app = matches.first else { throw VoxFailure("Could not uniquely find running app “\(name)”.") }
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw VoxFailure("Use Vox’s menu to quit Vox.") }
            guard app.terminate() else { throw VoxFailure("The app declined to quit. Check it for an unsaved document dialog.") }
        case .openURL(let raw):
            let value = raw.contains("://") ? raw : "https://\(raw)"
            guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else { throw VoxFailure("Use a valid http or https address.") }
            guard NSWorkspace.shared.open(url) else { throw VoxFailure("Could not open that address.") }
            try await Task.sleep(nanoseconds: 350_000_000)
            targetApp = NSWorkspace.shared.frontmostApplication
        case .search(let query):
            var url = URLComponents(string: "https://www.google.com/search")!
            url.queryItems = [URLQueryItem(name: "q", value: query)]
            guard let destination = url.url, NSWorkspace.shared.open(destination) else { throw VoxFailure("Could not open search.") }
            try await Task.sleep(nanoseconds: 350_000_000)
            targetApp = NSWorkspace.shared.frontmostApplication
        case .typeText(let text):
            try requireAccessibility(); try await focusTarget()
            let units = Array(text.utf16)
            // CGEvent supports short Unicode chunks; no clipboard overwrite or restore race.
            for offset in stride(from: 0, to: units.count, by: 20) {
                try Task.checkCancellation()
                let chunk = Array(units[offset..<min(offset + 20, units.count)])
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { throw VoxFailure("Cannot create keyboard event.") }
                chunk.withUnsafeBufferPointer { buffer in
                    down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress!)
                    up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress!)
                }
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                try await Task.sleep(nanoseconds: 8_000_000)
            }
        case .shortcut(let combo):
            try requireAccessibility(); try await focusTarget(); try press(combo)
        case .showNumbers:
            try requireAccessibility(); try await focusTarget(); try showNumbers()
            return "Numbered \(targets.count) controls in \(targetApp?.localizedName ?? "app"). Say “click 12”."
        case .hideNumbers: hideNumbers()
        case .clickNumber(let number):
            try requireAccessibility(); try await focusTarget()
            guard numberedPID == targetApp?.processIdentifier, let target = targets.first(where: { $0.id == number }) else { throw VoxFailure("Say “show numbers” in this app first.") }
            try click(target.element); hideNumbers()
        case .click(let label):
            try requireAccessibility(); try await focusTarget()
            let all = try scanControls()
            let exact = all.filter { $0.label.localizedCaseInsensitiveCompare(label) == .orderedSame }
            let matches = exact.isEmpty ? all.filter { $0.label.localizedCaseInsensitiveContains(label) } : exact
            guard matches.count == 1, let target = matches.first else {
                throw VoxFailure(matches.isEmpty ? "No accessible control named “\(label)”. Try “show numbers”." : "More than one control matches “\(label)”. Use “show numbers” to choose.")
            }
            try click(target.element); hideNumbers()
        case .scroll(let direction, let amount):
            try requireAccessibility(); try await focusTarget()
            let vertical = direction == "up" ? amount : direction == "down" ? -amount : 0
            let horizontal = direction == "left" ? amount : direction == "right" ? -amount : 0
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(vertical), wheel2: Int32(horizontal), wheel3: 0) else { throw VoxFailure("Cannot create scroll event.") }
            event.post(tap: .cghidEventTap)
        case .window(let position):
            try requireAccessibility(); try await focusTarget(); try moveWindow(position)
        case .volume(let amount): _ = try await runner.run("/usr/bin/osascript", ["-e", "set volume output volume \(amount)"])
        case .mute(let muted): _ = try await runner.run("/usr/bin/osascript", ["-e", "set volume output muted \(muted ? "true" : "false")"])
        case .screenshot:
            guard CGPreflightScreenCaptureAccess() else {
                CGRequestScreenCaptureAccess()
                throw VoxFailure("Enable Screen Recording for Vox in System Settings, then retry the screenshot.")
            }
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let file = desktop.appendingPathComponent("Vox-\(Int(Date().timeIntervalSince1970)).png")
            _ = try await runner.run("/usr/sbin/screencapture", ["-x", file.path])
            return "Saved \(file.lastPathComponent) to Desktop."
        case .lock: try press("control command q")
        case .sleep: _ = try await runner.run("/usr/bin/pmset", ["sleepnow"])
        case .reveal(let raw):
            let aliases: [String: String] = ["downloads": "~/Downloads", "desktop": "~/Desktop", "documents": "~/Documents", "home": "~"]
            let path = NSString(string: aliases[raw.lowercased()] ?? raw).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { throw VoxFailure("That path does not exist: \(path)") }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .shell(let command):
            let output = try await runner.run("/bin/zsh", ["-c", command])
            return output.isEmpty ? "Shell command completed." : output
        case .wait(let seconds): try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        case .workflow: throw VoxFailure("Workflow was not expanded.")
        }
        return action.summary
    }

    private func press(_ combo: String) throws {
        try requireAccessibility()
        let parts = combo.lowercased().replacingOccurrences(of: "+", with: " ").split(separator: " ").map(String.init)
        var flags: CGEventFlags = []
        var key: String?
        for part in parts {
            switch part {
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            default:
                guard key == nil else { throw VoxFailure("Use one key with optional command, shift, option, or control modifiers.") }
                key = part
            }
        }
        let codes: [String: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,
            "]":30,"o":31,"u":32,"[":33,"i":34,"p":35,"return":36,"enter":36,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"tab":48,"space":49,"`":50,"delete":51,"escape":53,"esc":53,"left":123,"right":124,"down":125,"up":126,"home":115,"end":119,"pageup":116,"pagedown":121,"forwarddelete":117,"f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,"f8":100,"f9":101,"f10":109,"f11":103,"f12":111]
        guard let key, let code = codes[key], let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { throw VoxFailure("Unknown key. Try “press command shift s” or “press return”.") }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }

    private func appElement() throws -> AXUIElement {
        guard let app = targetApp, !app.isTerminated else { throw VoxFailure("No target app. Switch to an app first.") }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        return element
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 2, size.height > 2 else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func scanControls() throws -> [ControlTarget] {
        let app = try appElement()
        guard let root = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(root) == AXUIElementGetTypeID() else { throw VoxFailure("This app has no accessible focused window.") }
        var queue: [(AXUIElement, Int)] = [(root as! AXUIElement, 0)]
        var index = 0; var visited = Set<CFHashCode>(); var found: [ControlTarget] = []
        let deadline = Date().addingTimeInterval(2)
        let visible = NSScreen.screens.map { screen -> CGRect in
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            return CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        }
        while index < queue.count, index < 1200, found.count < 150, Date() < deadline {
            let (node, depth) = queue[index]; index += 1
            guard visited.insert(CFHash(node)).inserted else { continue }
            let role = attribute(node, kAXRoleAttribute) as? String ?? ""
            let actionable = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXLinkRole, kAXTextFieldRole, kAXTextAreaRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXComboBoxRole].contains(role)
            let enabled = attribute(node, kAXEnabledAttribute) as? Bool ?? true
            if actionable, enabled, let rect = frame(node), visible.contains(where: { $0.intersects(rect) }) {
                let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { attribute(node, $0) as? String }.first { !$0.isEmpty } ?? role.replacingOccurrences(of: "AX", with: "")
                found.append(ControlTarget(id: found.count + 1, label: String(title.prefix(120)), element: node, frame: rect))
            }
            if depth < 18, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] { queue += children.prefix(300).map { ($0, depth + 1) } }
        }
        return found
    }

    private func click(_ element: AXUIElement) throws {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return }
        guard let rect = frame(element) else { throw VoxFailure("That control moved or disappeared. Show numbers again.") }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left), let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { throw VoxFailure("Cannot create mouse event.") }
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }

    func hideNumbers() { overlays.forEach { $0.close() }; overlays.removeAll(); targets.removeAll(); numberedPID = nil }

    private func showNumbers() throws {
        hideNumbers(); targets = try scanControls()
        guard !targets.isEmpty else { throw VoxFailure("No accessible controls found. This app may not expose its interface to macOS Accessibility.") }
        numberedPID = targetApp?.processIdentifier
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.level = .floating; panel.backgroundColor = .clear
            panel.isOpaque = false; panel.hasShadow = false; panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = NumberOverlay(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.targets = targets.map { ($0.id, CGPoint(x: $0.frame.minX - screen.frame.minX, y: top - $0.frame.minY - screen.frame.minY)) }
            panel.contentView = view; panel.orderFrontRegardless(); overlays.append(panel)
        }
    }

    private func moveWindow(_ position: String) throws {
        let app = try appElement()
        guard let value = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { throw VoxFailure("No focused window to move.") }
        let window = value as! AXUIElement
        if position == "minimize" {
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else { throw VoxFailure("This window cannot be minimized.") }
            return
        }
        let current = frame(window) ?? .zero
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let cocoaCenter = CGPoint(x: current.midX, y: top - current.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaCenter) }) ?? NSScreen.main else { throw VoxFailure("No display found.") }
        let bounds = screen.visibleFrame
        var rect = bounds
        switch position {
        case "left": rect.size.width /= 2
        case "right": rect.size.width /= 2; rect.origin.x += rect.width
        case "top": rect.size.height /= 2; rect.origin.y += rect.height
        case "bottom": rect.size.height /= 2
        case "center": rect.size = CGSize(width: min(current.width, bounds.width), height: min(current.height, bounds.height)); rect.origin = CGPoint(x: bounds.midX - rect.width / 2, y: bounds.midY - rect.height / 2)
        default: break
        }
        var point = CGPoint(x: rect.minX, y: top - rect.maxY); var size = rect.size
        guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { throw VoxFailure("Cannot calculate window bounds.") }
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        guard moved == .success, resized == .success else { throw VoxFailure("This app restricts moving or resizing this window.") }
        hideNumbers()
    }
}

private final class NumberOverlay: NSView {
    var targets: [(Int, CGPoint)] = []
    override func draw(_ dirtyRect: NSRect) {
        for (number, point) in targets {
            let text = "\(number)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.black]
            let width = max(23, text.size(withAttributes: attrs).width + 10)
            let rect = CGRect(x: min(max(point.x, 0), bounds.width - width), y: min(max(point.y - 19, 0), bounds.height - 21), width: width, height: 21)
            NSColor(calibratedRed: 0.79, green: 0.98, blue: 0.39, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            text.draw(at: CGPoint(x: rect.minX + 5, y: rect.minY + 4), withAttributes: attrs)
        }
    }
}

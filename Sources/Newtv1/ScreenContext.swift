import AppKit
import ScreenCaptureKit
import Vision
import Newtv1Core

struct CapturedScreen: Identifiable {
    let id = UUID()
    let jpeg: Data
    let displayName: String
    let displayID: UInt32
    let frame: CGRect
    let capturedAt = Date()
    var preview: NSImage? { NSImage(data: jpeg) }
}

@MainActor
enum ScreenContext {
    static func capture(displayChoice: String) async throws -> CapturedScreen {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw Newtv1Failure("Allow Newtv1 in Privacy & Security → Screen & System Audio Recording, then reopen it. Nothing was captured or sent.")
        }
        guard #available(macOS 14, *) else { throw Newtv1Failure("Screen guidance requires macOS 14 or newer. Other modes remain available.") }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { String(id($0)) == displayChoice }) ?? NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.screens.first
        guard let screen else { throw Newtv1Failure("No screen is available.") }
        let contents = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = contents.displays.first(where: { $0.displayID == id(screen) }) else { throw Newtv1Failure("The selected display disconnected. Choose another display.") }
        let own = contents.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingWindows: own)
        let config = SCStreamConfiguration()
        let scale = min(1, 1600.0 / Double(display.width))
        config.width = max(1, Int(Double(display.width) * scale))
        config.height = max(1, Int(Double(display.height) * scale))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try Task.checkCancellation()
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78]), jpeg.count <= 5_000_000 else { throw Newtv1Failure("Could not prepare a reasonably sized screen preview.") }
        return CapturedScreen(jpeg: jpeg, displayName: screen.localizedName, displayID: display.displayID, frame: screen.frame)
    }

    static func id(_ screen: NSScreen) -> UInt32 { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }

    static func readText(_ screen: CapturedScreen) async throws -> String {
        let data = screen.jpeg
        return try await Task.detached(priority: .userInitiated) {
            guard let bitmap = NSBitmapImageRep(data: data), let image = bitmap.cgImage else { throw Newtv1Failure("Could not read this image.") }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

@MainActor
final class GuidanceOverlay {
    private var panels: [NSPanel] = []
    private var expiration: Task<Void, Never>?
    func hide() { expiration?.cancel(); expiration = nil; panels.forEach { $0.close() }; panels.removeAll() }
    func show(_ highlights: [ScreenHighlight], displayID: UInt32, frame: CGRect, color: NSColor) {
        hide()
        guard !highlights.isEmpty, highlights.allSatisfy(\.valid), let current = NSScreen.screens.first(where: { ScreenContext.id($0) == displayID }), current.frame == frame else { return }
        let panel = NSPanel(contentRect: current.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = GuideDrawing(frame: CGRect(origin: .zero, size: current.frame.size))
        view.highlights = highlights; view.color = color
        panel.contentView = view; panel.orderFrontRegardless(); panels.append(panel)
        expiration = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            self?.hide()
        }
    }
}

private final class GuideDrawing: NSView {
    var highlights: [ScreenHighlight] = []
    var color = NSColor.systemGreen
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        for (index, item) in highlights.enumerated() {
            let rect = CGRect(x: item.x * bounds.width, y: item.y * bounds.height, width: item.width * bounds.width, height: item.height * bounds.height)
            color.withAlphaComponent(0.1).setFill(); NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
            color.setStroke(); let border = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8); border.lineWidth = 3; border.stroke()
            let title = "\(index + 1)  \(item.label)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.black]
            let width = min(bounds.width - 12, title.size(withAttributes: attrs).width + 16)
            let label = CGRect(x: min(max(rect.minX, 6), bounds.width - width - 6), y: max(4, rect.minY - 28), width: width, height: 24)
            color.setFill(); NSBezierPath(roundedRect: label, xRadius: 6, yRadius: 6).fill()
            title.draw(in: label.insetBy(dx: 8, dy: 4), withAttributes: attrs)
        }
    }
}

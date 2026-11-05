import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchController: ObservableObject {
    @Published private(set) var expanded = false
    @Published private(set) var cutoutWidth: CGFloat = 180
    @Published private(set) var topHeight: CGFloat = 32
    @Published private(set) var panelWidth: CGFloat = 284
    @Published private(set) var panelHeight: CGFloat = 40
    @Published var pinned = false
    let model: AppModel
    private var panel: NotchPanel?
    private var dashboard: NSWindow?
    private var display: NSScreen?
    private var screenObserver: NSObjectProtocol?
    private var subscriptions = Set<AnyCancellable>()
    private var collapseTask: Task<Void, Never>?
    private var hovered = false

    init(model: AppModel) { self.model = model }

    func start() {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Newtv1 Notch"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: NotchView(controller: self, model: model, speech: model.speech).ignoresSafeArea().preferredColorScheme(.dark))
        self.panel = panel
        reposition()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        model.speech.$isListening.dropFirst().sink { [weak self] listening in
            guard let self, listening else { return }
            self.setExpanded(true); self.scheduleCollapse(after: 3)
        }.store(in: &subscriptions)
        model.$busy.dropFirst().sink { [weak self] busy in
            guard let self, busy else { return }
            self.setExpanded(true); self.scheduleCollapse(after: 3)
        }.store(in: &subscriptions)
        model.$error.dropFirst().sink { [weak self] error in
            guard let self, error != nil else { return }
            self.setExpanded(true); self.scheduleCollapse(after: 6)
        }.store(in: &subscriptions)
    }

    private func reposition() {
        display = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
        guard let screen = display else { return }
        topHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            cutoutWidth = max(120, right.minX - left.maxX)
        } else { cutoutWidth = 180 }
        applyFrame()
    }

    private func applyFrame() {
        guard let screen = display, let panel else { return }
        let width = min(screen.frame.width - 32, expanded ? max(420, cutoutWidth + 128) : cutoutWidth + 104)
        let height = expanded ? topHeight + 224 : topHeight + 8
        panelWidth = width; panelHeight = height
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func setExpanded(_ value: Bool) {
        collapseTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { expanded = value }
        applyFrame()
    }

    func hover(_ value: Bool) {
        hovered = value
        if value { setExpanded(true) } else { scheduleCollapse(after: 0.65) }
    }

    private func scheduleCollapse(after seconds: Double) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
            guard let self, !self.hovered, !self.pinned else { return }
            self.setExpanded(false)
        }
    }

    func togglePin() {
        pinned.toggle()
        if pinned { setExpanded(true) } else if !hovered { scheduleCollapse(after: 0.65) }
    }
    func reveal() { setExpanded(true); scheduleCollapse(after: 4) }

    func openCommandCenter() {
        if dashboard == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Newtv1"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 1040, height: 740)
            window.contentView = NSHostingView(rootView: ContentView(model: model, speech: model.speech).frame(minWidth: 1040, minHeight: 740).preferredColorScheme(.dark))
            window.center()
            dashboard = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.makeKeyAndOrderFront(nil)
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct NotchView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    private let green = Color(red: 0.79, green: 0.97, blue: 0.43)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { model.toggleListening() } label: {
                    Image(systemName: speech.isListening ? "waveform" : "mic.slash.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(speech.isListening ? green : Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain).help("Toggle Newtv1 listening (Option–Space)")
                Color.clear.frame(width: controller.cutoutWidth)
                Button { controller.togglePin() } label: {
                    Group {
                        if model.busy { ProgressView().controlSize(.mini).tint(green) }
                        else { Image(systemName: model.error != nil ? "exclamationmark.circle.fill" : "sparkle").foregroundStyle(model.error != nil ? .orange : green) }
                    }.font(.system(size: 12)).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain).help("Pin or expand Newtv1")
            }.frame(height: controller.topHeight)
            if controller.expanded {
                expandedContent.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 16)
                    .transition(.opacity)
            } else { Color.clear.frame(height: 8) }
        }
        .frame(width: controller.panelWidth, height: controller.panelHeight, alignment: .top)
        .background(NotchShape().fill(.black))
        .clipShape(NotchShape())
        .overlay(alignment: .bottom) { if speech.isListening { Capsule().fill(green.opacity(0.7)).frame(width: 34 + CGFloat(speech.level) * 45, height: 2).padding(.bottom, 3) } }
        .onHover { controller.hover($0) }
        .accessibilityElement(children: .contain).accessibilityLabel("Newtv1 notch controls")
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(green)
                Text("Newtv1").font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Text(model.busy ? "WORKING" : speech.isListening ? "LISTENING" : "STANDBY")
                    .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(speech.isListening ? green : .gray)
                Button { controller.togglePin() } label: { Image(systemName: controller.pinned ? "pin.fill" : "pin").foregroundStyle(controller.pinned ? green : .gray) }.buttonStyle(.plain).help("Keep expanded")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.error != nil ? "Needs your attention" : model.busy ? "Making it happen." : speech.isListening ? "Your next move?" : "Your Mac, one phrase away.")
                    .font(.system(size: 19, weight: .medium)).tracking(-0.5)
                Text(model.error ?? (speech.transcript.isEmpty ? (model.wakeWord ? "Say “New TV One, open Safari”." : "Start listening, then say a command.") : speech.transcript))
                    .font(.system(size: 11)).foregroundStyle(model.error != nil ? Color.orange : Color.white.opacity(0.48)).lineLimit(2).frame(height: 30, alignment: .top)
            }
            HStack(spacing: 8) {
                Button { model.toggleListening() } label: {
                    Label(model.speechStarting ? "Starting…" : speech.isListening ? "Stop listening" : "Start listening", systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 10).background(green, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).disabled(model.speechStarting)
                Button { model.stop(); speech.stop() } label: { Image(systemName: "stop.circle").font(.system(size: 16)).foregroundStyle(.orange).frame(width: 36, height: 34).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain).help("Stop all actions")
                Button { model.openCommandCenter() } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)).frame(width: 36, height: 34).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain).help("Open command center")
            }
            HStack(spacing: 6) {
                Circle().fill(model.accessibility ? green : .orange).frame(width: 4, height: 4)
                Button(model.accessibility ? model.targetName : "Set up Accessibility") { model.openCommandCenter(page: model.accessibility ? .control : .settings) }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
                Spacer()
                Button { model.openCommandCenter(page: .brain) } label: { Image(systemName: "sparkles") }.buttonStyle(.plain).foregroundStyle(green).help("Open Brain")
                Text("⌥ SPACE").font(.system(size: 9, design: .monospaced)).foregroundStyle(.gray)
            }
        }
    }
}

private struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = min(22, rect.height / 2)
        var path = Path()
        path.move(to: rect.origin)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

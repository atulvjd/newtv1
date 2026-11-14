import AppKit
import SwiftUI
import Combine
import Newtv1Core

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
    private var hoverTask: Task<Void, Never>?
    private var frameTimer: Timer?
    private var motionToken = UUID()
    private var gridMeasurement: NotchGridMeasurement?
    var showsBody: Bool { expanded || panelHeight > topHeight + 12 }
    var bodyVisibility: Double {
        let config = model.notch.normalized()
        let target = config.expansionLayout == .horizontal ? config.horizontalHeight + NotchGeometry.horizontalControlsHeight : config.contentHeight
        return min(max(Double(panelHeight - topHeight - 45) / max(1, min(125, target - 45)), 0), 1)
    }

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
        panel.contentView = NSHostingView(rootView: NotchView(controller: self, model: model, speech: model.speech, speaker: model.speaker).ignoresSafeArea().preferredColorScheme(.dark))
        self.panel = panel
        pinned = model.notch.pinnedOnLaunch
        expanded = pinned
        model.onPreviewNotch = { [weak self] in self?.reveal() }
        reposition()
        model.$notch.dropFirst().sink { [weak self] _ in
            // Published values arrive before assignment; apply on the next main turn.
            Task { @MainActor [weak self] in self?.reposition() }
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition(); self?.model.objectWillChange.send() }
        }
        model.speech.$isListening.dropFirst().sink { [weak self] listening in
            guard let self, listening, self.model.notch.expandOnListening else { return }
            self.setExpanded(true); self.scheduleCollapse(after: 3)
        }.store(in: &subscriptions)
        model.$busy.dropFirst().sink { [weak self] busy in
            guard let self, busy, self.model.notch.expandOnExecution else { return }
            self.setExpanded(true); self.scheduleCollapse(after: 3)
        }.store(in: &subscriptions)
        model.$error.dropFirst().sink { [weak self] error in
            guard let self, error != nil, self.model.notch.expandOnError else { return }
            self.setExpanded(true); self.scheduleCollapse(after: 6)
        }.store(in: &subscriptions)
    }

    private func reposition() {
        let choice = model.notch.displayID
        if choice == "main" { display = NSScreen.screens.first }
        else if choice != "automatic" {
            display = NSScreen.screens.first { String(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) == choice }
        } else { display = nil }
        if display == nil || !NSScreen.screens.contains(where: { $0 == display }) {
            display = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
        }
        applyFrame()
    }

    private func applyFrame(animated: Bool = false) {
        guard let screen = display, let panel else { return }
        var hardwareWidth: CGFloat = 180
        var center = screen.frame.midX
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            hardwareWidth = max(120, right.minX - left.maxX)
            center = (left.maxX + right.minX) / 2
        }
        let baseLayout = NotchGeometry.calculate(screen: screen.frame, hardwareWidth: hardwareWidth, hardwareHeight: screen.safeAreaInsets.top, hardwareCenter: center, expanded: expanded, configuration: model.notch)
        let configuration = model.notch.normalized()
        let measurement = gridMeasurement.flatMap { measured -> CGFloat? in
            guard abs(measured.width - (baseLayout.frame.width - 36)) < 1,
                  measured.sections == configuration.visibleSections,
                  measured.rowHeight == configuration.horizontalHeight else { return nil }
            return measured.height
        }
        let layout = NotchGeometry.calculate(screen: screen.frame, hardwareWidth: hardwareWidth, hardwareHeight: screen.safeAreaInsets.top, hardwareCenter: center, expanded: expanded, configuration: configuration, measuredGridHeight: measurement)
        cutoutWidth = layout.cutoutWidth; topHeight = layout.headerHeight
        frameTimer?.invalidate(); frameTimer = nil
        motionToken = UUID()
        let token = motionToken
        let shouldAnimate = animated && model.notch.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && panel.frame.width > 0
        if shouldAnimate {
            let from = panel.frame
            let target = layout.frame
            let opening = expanded
            let duration = opening ? 0.42 : 0.26
            let started = ProcessInfo.processInfo.systemUptime
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                Task { @MainActor [weak self] in
                    guard let self, self.motionToken == token else { timer.invalidate(); return }
                    let progress = min((ProcessInfo.processInfo.systemUptime - started) / duration, 1)
                    self.displayFrame(NotchMotion.frame(from: from, to: target, progress: progress, opening: opening))
                    if progress >= 1 { timer.invalidate(); self.frameTimer = nil }
                }
            }
            frameTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else { displayFrame(layout.frame) }
        panel.orderFrontRegardless()
    }

    func updateGridMeasurement(_ measurement: NotchGridMeasurement) {
        guard expanded, frameTimer == nil, measurement.height.isFinite, measurement.height >= 0,
              abs(measurement.width - (panelWidth - 36)) < 1 else { return }
        if let previous = gridMeasurement,
           previous.sections == measurement.sections,
           previous.rowHeight == measurement.rowHeight,
           abs(previous.width - measurement.width) < 1,
           abs(previous.height - measurement.height) < 1 { return }
        gridMeasurement = measurement
        applyFrame()
    }

    private func displayFrame(_ frame: CGRect) {
        // The view and native panel advance together, preserving the top edge and click targets.
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            panelWidth = frame.width; panelHeight = frame.height
            panel?.setFrame(frame, display: true)
        }
    }

    func setExpanded(_ value: Bool) {
        collapseTask?.cancel(); hoverTask?.cancel()
        let changed = expanded != value
        expanded = value
        applyFrame(animated: changed)
    }

    func hover(_ value: Bool) {
        hovered = value; hoverTask?.cancel()
        if value {
            collapseTask?.cancel()
            guard model.notch.hoverToExpand, !expanded else { return }
            hoverTask = Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(nanoseconds: UInt64(self.model.notch.hoverDelay * 1_000_000_000)) } catch { return }
                if self.hovered { self.setExpanded(true) }
            }
        } else { scheduleCollapse(after: model.notch.collapseDelay) }
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
        if pinned { setExpanded(true) } else if !hovered { scheduleCollapse(after: model.notch.collapseDelay) }
    }
    func reveal() { setExpanded(true); scheduleCollapse(after: 6) }

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

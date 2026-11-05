import SwiftUI
import AppKit

@main
struct VoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("Vox") {
            ContentView(model: model, speech: model.speech)
                .frame(minWidth: 1040, minHeight: 740)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Toggle Microphone") { model.toggleListening() }.keyboardShortcut(" ", modifiers: [.option])
                Button("Stop All Actions") { model.stop(); model.speech.stop() }.keyboardShortcut(".", modifiers: [.command])
            }
        }
        MenuBarExtra("Vox", systemImage: "waveform.circle.fill") {
            Button(model.speech.isListening ? "Stop Listening" : "Start Listening  ⌥Space") { model.toggleListening() }
            Button("Open Command Center") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Stop All Actions") { model.stop(); model.speech.stop() }
            Button("Quit Vox") { model.stop(); model.speech.stop(); NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil) }
        return true
    }
}

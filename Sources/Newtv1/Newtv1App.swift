import SwiftUI
import AppKit

@main
struct Newtv1App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("Newtv1", systemImage: "waveform.circle.fill") {
            Newtv1Menu(model: delegate.model, speech: delegate.model.speech)
        }
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Open Command Center") { delegate.model.openCommandCenter() }
                    Button("Stop All Actions") { delegate.model.stop(); delegate.model.speech.stop() }.keyboardShortcut(".", modifiers: [.command])
                }
            }
    }
}

private struct Newtv1Menu: View {
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    var body: some View {
        Button(speech.isListening ? "Stop Listening" : "Start Listening  ⌥Space") { model.toggleListening() }
        Button("Talk with Newt") { model.openCommandCenter(page: .companion) }
        Button("Tasks") { model.openCommandCenter(page: .jobs) }
        Button("Open Command Center") { model.openCommandCenter() }
        Button("Customize Notch") { model.openCommandCenter(page: .notch) }
        Button("Settings") { model.openCommandCenter(page: .settings) }
        Divider()
        Button("Stop All Actions") { model.stop(); speech.stop() }
        Button("Quit Newtv1") { NSApp.terminate(nil) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var desktop: NotchController?
    private var captions: CaptionController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let desktop = NotchController(model: model)
        self.desktop = desktop
        model.onOpenCommandCenter = { [weak desktop] in desktop?.openCommandCenter() }
        captions = CaptionController(speaker: model.speaker)
        desktop.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        desktop?.reveal(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.stop(); model.speech.stop() }
}

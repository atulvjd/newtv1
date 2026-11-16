import SwiftUI
import Combine
import Newtv1Core

private typealias ControlViewState<T> = SwiftUI.State<T>

struct SystemControlsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var system: SystemControls
    @ControlViewState private var microphoneDraft = 0.0
    @ControlViewState private var editingMicrophone = false
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private var unavailable: Bool { model.busy || model.capturingScreen || model.pending != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                WorkspaceHeading(title: "Your Mac, within reach.", subtitle: "System controls you can click, speak, or combine into a workflow.")
                Spacer()
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(WorkspaceButtonStyle()).help("Refresh system state")
            }
            ScreenAccessView(model: model)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18, alignment: .top)], spacing: 18) {
                card("Wi-Fi", icon: "wifi") {
                    Text(system.wifiOn.map { $0 ? "Wi-Fi is on" : "Wi-Fi is off" } ?? "No Wi-Fi interface available").foregroundStyle(WorkspaceTheme.secondary)
                    HStack {
                        if let enabled = system.wifiOn { Button(enabled ? "Turn off Wi-Fi…" : "Turn on Wi-Fi") { model.submit(enabled ? "wifi off" : "wifi on") }.buttonStyle(WorkspaceButtonStyle()) }
                        Button("Settings") { model.submit("open wifi settings") }.buttonStyle(.plain).foregroundStyle(WorkspaceTheme.accent)
                    }
                    Text("Turning off requires review and disconnects wireless networking.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                card("Appearance & Dock", icon: "circle.lefthalf.filled") {
                    HStack { Button("Light") { model.submit("light mode") }; Button("Dark") { model.submit("dark mode") } }.buttonStyle(WorkspaceButtonStyle())
                    HStack { Button("Auto-hide Dock") { model.submit("hide dock") }; Button("Show Dock") { model.submit("show dock") } }.buttonStyle(WorkspaceButtonStyle())
                    Text("Uses macOS Automation access to System Events.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                card("Sound output", icon: "speaker.wave.2") {
                    devicePicker(.output)
                    HStack { Button("−10%") { model.submit("volume down") }; Button("+10%") { model.submit("volume up") } }.buttonStyle(WorkspaceButtonStyle())
                    HStack { Button("Mute") { model.submit("mute") }; Button("Unmute") { model.submit("unmute") } }.buttonStyle(WorkspaceButtonStyle())
                    Text("Say “audio output” followed by the exact device name.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                card("Microphone", icon: system.microphoneMuted ? "mic.slash" : "mic") {
                    devicePicker(.input)
                    if system.microphoneLevel != nil {
                        HStack { Slider(value: $microphoneDraft, in: 0...100, onEditingChanged: { editing in
                            editingMicrophone = editing
                            if !editing { model.submit("microphone volume \(Int(round(microphoneDraft)))") }
                        }).accessibilityLabel("System microphone input volume"); Text("\(Int(microphoneDraft))%").monospacedDigit().frame(width: 38) }
                    } else { Text("This device has no adjustable input level.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary) }
                    Button(system.microphoneMuted ? "Unmute microphone" : "Mute microphone") { model.submit(system.microphoneMuted ? "unmute microphone" : "mute microphone") }.buttonStyle(WorkspaceButtonStyle())
                    Text("Muting affects the system input. Use this button to restore it when Newt cannot hear you.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                card("Keep awake", icon: "cup.and.saucer") {
                    if let end = system.awakeUntil {
                        HStack { Text("Session remaining"); Spacer(); Text(end, style: .timer).monospacedDigit().foregroundStyle(WorkspaceTheme.accent) }
                        Button("End keep-awake session") { model.submit("allow sleep") }.buttonStyle(WorkspaceButtonStyle())
                    } else {
                        HStack { ForEach([15, 30, 60], id: \.self) { minutes in Button("\(minutes) min") { model.submit("keep awake for \(minutes) minutes") } } }.buttonStyle(WorkspaceButtonStyle())
                    }
                    Text("Prevents idle system sleep for up to 3 hours. The display may sleep. Ends on timeout, Stop All or quitting.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                card("Display & playback", icon: "display") {
                    HStack { Button { model.submit("brightness down") } label: { Image(systemName: "sun.min") }; Button { model.submit("brightness up") } label: { Image(systemName: "sun.max") }; Button("Sleep display…") { model.submit("sleep display") } }.buttonStyle(WorkspaceButtonStyle())
                    HStack {
                        Button { model.submit("previous track") } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Previous track")
                        Button { model.submit("play pause") } label: { Image(systemName: "playpause.fill") }.accessibilityLabel("Play or pause media")
                        Button { model.submit("next track") } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Next track")
                    }.buttonStyle(WorkspaceButtonStyle())
                    Text("Brightness keys need a compatible display; media keys use macOS’s active player. Mac control access is required.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                card("Window layouts", icon: "rectangle.split.2x2") {
                    Text("Target: \(model.targetName)").foregroundStyle(WorkspaceTheme.secondary).lineLimit(1)
                    HStack { layoutButton("Top left", "top left quarter"); layoutButton("Top right", "top right quarter") }
                    HStack { layoutButton("Bottom left", "bottom left quarter"); layoutButton("Bottom right", "bottom right quarter") }
                    Text("Respects the display’s menu bar and Dock. Some apps enforce minimum window sizes.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                }
                card("System Settings", icon: "gearshape") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 10) {
                        ForEach(SettingsPane.allCases, id: \.self) { pane in Button(pane.title) { model.submit("open \(pane.rawValue) settings") }.buttonStyle(.plain).foregroundStyle(WorkspaceTheme.accent).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
            }.disabled(unavailable)
        }.onAppear { refresh() }.onReceive(timer) { _ in refresh() }
    }
    private func refresh() {
        system.refresh()
        if !editingMicrophone { microphoneDraft = Double(system.microphoneLevel ?? 0) * 100 }
    }
    private func devicePicker(_ direction: AudioDirection) -> some View {
        let devices = direction == .input ? system.inputs : system.outputs
        return Picker(direction == .input ? "Input device" : "Output device", selection: Binding(get: { direction == .input ? system.inputID : system.outputID }, set: { id in
            model.submit("audio \(direction.rawValue) " + id)
        })) {
            if devices.isEmpty { Text("No device available").tag("") }
            ForEach(devices) { device in Text(device.name).tag(device.id) }
        }.labelsHidden()
    }
    private func layoutButton(_ title: String, _ command: String) -> some View {
        Button(title) { model.submit(command) }.buttonStyle(WorkspaceButtonStyle())
    }
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.system(size: 15, weight: .medium))
            content().font(.system(size: 12))
        }.padding(22).frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading).workspaceCard()
    }
}

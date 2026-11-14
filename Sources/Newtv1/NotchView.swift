import SwiftUI
import AppKit
import Newtv1Core

extension NotchConfiguration {
    var tint: Color {
        let hex = UInt64(normalized().accentHex, radix: 16) ?? 0xC9F76E
        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct NotchShape: Shape {
    var radius: CGFloat
    var floating: Bool
    func path(in rect: CGRect) -> Path {
        if floating { return Path(roundedRect: rect, cornerRadius: min(radius, rect.height / 2)) }
        let r = min(radius, rect.height / 2)
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

struct NotchSurface: View {
    let config: NotchConfiguration
    var body: some View {
        let shape = NotchShape(radius: config.cornerRadius, floating: config.style == .floating)
        ZStack {
            if config.finish == .glass { shape.fill(.ultraThinMaterial) }
            shape.fill(Color.black.opacity(config.finish == .glass ? config.opacity * 0.65 : config.opacity))
            if config.finish == .gradient {
                LinearGradient(colors: [config.tint.opacity(0.22), .clear, config.tint.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing).clipShape(shape)
            }
            shape.stroke(config.tint.opacity(config.borderOpacity), lineWidth: 1)
        }.clipShape(shape)
    }
}

struct NotchView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    @ObservedObject var speaker: AnswerSpeaker
    private var config: NotchConfiguration { model.notch.normalized() }
    private var tint: Color { config.tint }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                wing(config.leftWing).frame(width: config.wingWidth)
                if config.style == .attached { Color.clear.frame(width: controller.cutoutWidth) }
                else { Text("Newt").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.65)).frame(width: 116) }
                wing(config.rightWing).frame(width: config.wingWidth)
                Spacer(minLength: 0)
            }.frame(height: controller.topHeight)
                .background(config.style == .attached ? Color.black : .clear)
            if controller.showsBody {
                Group {
                if config.expansionLayout == .horizontal { horizontalBody } else {
                VStack(spacing: 0) {
                    HStack(spacing: 9) {
                        NewtSignal(state: signalState, level: speech.level, tint: tint, animated: config.animations).frame(width: 24, height: 24)
                        Text("Newtv1").font(.system(size: 16, weight: .semibold, design: .rounded))
                        Menu {
                            ForEach(AssistantMode.allCases) { mode in Button { model.assistantMode = mode } label: { Label(mode.title, systemImage: mode.icon) } }
                        } label: { Label(model.assistantMode.title, systemImage: model.assistantMode.icon).font(.system(size: 10)).foregroundStyle(tint) }.menuStyle(.borderlessButton).fixedSize()
                        Spacer()
                        Text(model.busy ? "WORKING" : speaker.speaking ? "SPEAKING" : speech.isListening ? "LISTENING" : "READY").font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(tint)
                        Button { model.openCommandCenter(page: .notch) } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).help("Customize notch")
                        Button { controller.togglePin() } label: { Image(systemName: controller.pinned ? "pin.fill" : "pin") }.buttonStyle(.plain).foregroundStyle(controller.pinned ? tint : .gray).help("Pin expanded notch")
                    }.padding(.horizontal, 20).padding(.vertical, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: config.compactRows ? 10 : 16) {
                            ForEach(config.visibleSections) { section in
                                NotchModule(section: section, model: model, speech: speech)
                            }
                        }.padding(.horizontal, 20).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 0, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .clipped()
                    Divider().overlay(tint.opacity(0.12))
                    HStack(spacing: 9) {
                        Button { model.toggleListening() } label: {
                            Label(model.speechStarting ? "Cancel microphone startup" : speech.isListening ? "Stop listening" : model.assistantMode == .dictate ? "Start dictation" : "Start listening", systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 10).background(tint, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                        Button { model.stop(); speech.stop() } label: { Image(systemName: "stop.circle").font(.system(size: 17)).foregroundStyle(.orange).frame(width: 34, height: 34).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain).help("Stop all actions")
                        Button { model.openCommandCenter(page: .brain) } label: { Image(systemName: "sparkles").frame(width: 32, height: 34) }.buttonStyle(.plain).help("Open Brain")
                        Button { model.openCommandCenter(page: .companion) } label: { Image(systemName: "arrow.up.right.square").frame(width: 32, height: 34) }.buttonStyle(.plain).help("Open Newt companion")
                    }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 14)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(Color.black)
                }
                }
                }.frame(maxHeight: .infinity)
                    .opacity(controller.bodyVisibility)
                    .offset(y: (1 - controller.bodyVisibility) * 7)
                    .allowsHitTesting(controller.expanded && controller.bodyVisibility > 0.85)
                    .accessibilityHidden(!controller.expanded || controller.bodyVisibility < 0.85)
            } else { Color.clear.frame(height: 8) }
        }
        .frame(width: controller.panelWidth, height: controller.panelHeight, alignment: .top)
        .background(NotchSurface(config: config))
        .clipShape(NotchShape(radius: config.cornerRadius, floating: config.style == .floating))
        .overlay(alignment: .bottom) {
            if config.showWaveform, speech.isListening {
                ListeningRibbon(level: speech.level, tint: tint, animated: config.animations).padding(.bottom, 2)
            }
        }
        .tint(tint)
        .onHover { controller.hover($0) }
        .accessibilityElement(children: .contain).accessibilityLabel("Newtv1 customizable notch")
    }

    private var horizontalBody: some View {
        VStack(spacing: 10) {
            NotchModulesGrid(width: max(1, controller.panelWidth - 36), model: model, speech: speech)
                .onPreferenceChange(NotchGridMeasurementKey.self) { measurement in
                    if let measurement {
                        Task { @MainActor in controller.updateGridMeasurement(measurement) }
                    }
                }
            Divider().overlay(tint.opacity(0.12))
            horizontalControls
                .frame(height: 34)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var horizontalControls: some View {
        HStack(spacing: 14) {
            if controller.panelWidth > 700 {
                HStack(spacing: 8) {
                    NewtSignal(state: signalState, level: speech.level, tint: tint, animated: config.animations)
                        .frame(width: 24, height: 24)
                    Text("Newtv1").font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Menu {
                    ForEach(AssistantMode.allCases) { mode in
                        Button { model.assistantMode = mode } label: { Label(mode.title, systemImage: mode.icon) }
                    }
                } label: {
                    Label(model.assistantMode.title, systemImage: model.assistantMode.icon)
                        .font(.system(size: 10)).foregroundStyle(tint)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Button { model.openCommandCenter(page: .notch) } label: {
                Image(systemName: "slider.horizontal.3")
            }.help("Customize notch")
            Button { controller.togglePin() } label: {
                Image(systemName: controller.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(controller.pinned ? tint : .gray)
            }.help("Pin expanded notch")
            Spacer(minLength: 0)
            Button { model.toggleListening() } label: {
                Label(model.speechStarting ? "Cancel microphone startup" : speech.isListening ? "Stop listening" : model.assistantMode == .dictate ? "Start dictation" : "Start listening", systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(tint, in: RoundedRectangle(cornerRadius: 9))
            }
            Button { model.stop(); speech.stop() } label: {
                Image(systemName: "stop.circle").foregroundStyle(.orange)
            }.help("Stop all actions")
            Button { model.openCommandCenter(page: .brain) } label: {
                Image(systemName: "sparkles")
            }.help("Open Brain")
            Button { model.openCommandCenter(page: .companion) } label: {
                Image(systemName: "arrow.up.right.square")
            }.help("Open Newt companion")
            if controller.panelWidth > 1000 {
                Spacer(minLength: 0)
                Text(model.busy ? "WORKING" : speaker.speaking ? "SPEAKING" : speech.isListening ? "LISTENING" : "READY")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(tint)
            }
        }
        .buttonStyle(.plain)
    }

    private var signalState: NewtSignalState {
        model.error != nil ? .attention : model.busy || model.speechStarting ? .working : speech.isListening || speaker.speaking ? .listening : .idle
    }

    @ViewBuilder private func wing(_ action: NotchWingAction) -> some View {
        if action == .clock {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Button { controller.togglePin() } label: { Text(context.date, style: .time).font(.system(size: 9, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity, maxHeight: .infinity) }.buttonStyle(.plain)
            }
        } else {
            Button { perform(action) } label: {
                Group {
                    if action == .expand || action == .microphone && speech.isListening {
                        NewtSignal(state: signalState, level: speech.level, tint: tint, animated: config.animations).frame(width: 28, height: 28)
                    } else {
                        Image(systemName: action == .microphone ? "mic.slash.fill" : action.icon)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(action == .microphone ? Color.gray : tint)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).help(action.title)
        }
    }

    private func perform(_ action: NotchWingAction) {
        switch action {
        case .microphone: model.toggleListening()
        case .expand, .clock: controller.togglePin()
        case .brain: model.openCommandCenter(page: .brain)
        case .commandCenter: model.openCommandCenter()
        case .showNumbers: model.submit("show numbers")
        case .screenshot: model.submit("take a screenshot")
        }
    }
}

struct NotchModule: View {
    let section: NotchSection
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    private var tint: Color { model.notch.tint }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(section.title.uppercased(), systemImage: section.icon).font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(tint.opacity(0.7))
            content
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .audio: AudioModule(audio: model.audio)
        case .calendar: CalendarModule(calendar: model.calendar)
        case .downloads: DownloadsModule(files: model.files)
        case .shelf: FileShelfModule(files: model.files)
        case .system: SystemModule(monitor: model.monitor)
        case .camera: CameraModule(camera: model.camera)
        case .clipboard: ClipboardModule(clipboard: model.clipboard)
        case .inbox: InboxModule(notices: model.notices)
        case .routines: RoutineModule(routines: model.routines, model: model)
        case .media:
            NowPlayingView(media: model.nowPlaying, tint: tint)
        case .voice:
            Text(model.error != nil ? "Needs your attention" : model.busy ? "Making it happen." : model.assistantMode == .dictate ? "Dictating into \(model.targetName)" : speech.isListening ? "I'm listening." : "Newt, at your side.").font(.system(size: 18, weight: .medium)).tracking(-0.4)
            Text(model.error ?? (speech.transcript.isEmpty ? model.assistantMode.hint : speech.transcript)).font(.system(size: 11)).foregroundStyle(model.error != nil ? Color.orange : .gray).lineLimit(3)
            if speech.isListening { Text(speech.status).font(.system(size: 10)).foregroundStyle(tint) }
            Button(model.accessibility ? "Target: \(model.targetName)" : "Set up Accessibility") { model.openCommandCenter(page: model.accessibility ? .control : .settings) }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.gray)
        case .shortcuts:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 7)], spacing: 7) {
                ForEach(model.notch.shortcuts) { shortcut in
                    Button { model.submit(shortcut.command) } label: {
                        Label(shortcut.title, systemImage: NSImage(systemSymbolName: shortcut.icon, accessibilityDescription: nil) == nil ? "bolt" : shortcut.icon).font(.system(size: 10)).lineLimit(1).frame(maxWidth: .infinity).padding(9).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(model.busy || model.pending != nil).help(shortcut.command)
                }
            }
            if model.notch.shortcuts.isEmpty { Text("Add your own buttons in Notch Studio.").font(.system(size: 11)).foregroundStyle(.gray) }
        case .workflows:
            if model.workflows.isEmpty { Text("Create a workflow in the command center.").font(.system(size: 11)).foregroundStyle(.gray) }
            ForEach(model.workflows.prefix(model.notch.compactRows ? 2 : 4)) { workflow in
                Button { model.submit("run \(workflow.name)") } label: { HStack { Text(workflow.name).font(.system(size: 11)); Spacer(); Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(tint) }.padding(9).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).disabled(model.busy || model.pending != nil)
            }
        case .activity:
            if let recent = model.activities.first {
                Text(recent.command).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(recent.detail).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(model.notch.compactRows ? 1 : 3)
            } else { Text("Your next command will appear here.").font(.system(size: 11)).foregroundStyle(.gray) }
        case .clock:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline) {
                    Text(context.date, style: .time).font(.system(size: 27, weight: .light, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.system(size: 10)).foregroundStyle(.gray)
                }
            }
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    if let end = model.notchTimerEnd {
                        let remaining = max(0, Int(ceil(end.timeIntervalSince(context.date))))
                        Text(String(format: "%02d:%02d", remaining / 60, remaining % 60)).font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                        Spacer(); Button("Cancel") { model.cancelNotchTimer() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.gray)
                    } else {
                        if model.notchTimerFinished { Text("Timer finished").font(.system(size: 11)).foregroundStyle(tint) }
                        ForEach([5, 15, 25], id: \.self) { minutes in Button("\(minutes)m") { model.startNotchTimer(minutes: minutes) }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 7).background(.white.opacity(0.06), in: Capsule()) }
                    }
                }
            }
        case .notes:
            Text(model.scratchpad.isEmpty ? "A thought worth keeping?" : model.scratchpad).font(.system(size: 11)).foregroundStyle(model.scratchpad.isEmpty ? .gray : .white.opacity(0.8)).lineLimit(model.notch.compactRows ? 2 : 5)
            Button("Edit scratchpad ↗") { model.openCommandCenter(page: .notch) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(tint)
        }
    }
}

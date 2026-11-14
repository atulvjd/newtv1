import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Newtv1Core

private typealias StudioState<Value> = SwiftUI.State<Value>

struct NotchStudio: View {
    @ObservedObject var model: AppModel
    @StudioState private var tab = "Appearance"
    @StudioState private var message: String?
    @StudioState private var shortcutTitle = ""
    @StudioState private var shortcutIcon = "bolt"
    @StudioState private var shortcutCommand = ""
    @StudioState private var editingID: UUID?
    @StudioState private var previewHeight: CGFloat = 314
    private var tint: Color { model.notch.tint }
    private let card = Color.white.opacity(0.035)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make the notch yours.").font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                    Text("Your layout. Your shortcuts. Every change appears live.").font(.system(size: 12)).foregroundStyle(.gray)
                }
                Spacer()
                Menu { Button("Import profile…", action: importProfile); Button("Export profile…", action: exportProfile); Divider(); Button("Reset notch settings") { model.notch = NotchConfiguration(); message = "Notch settings reset. Your workflows, notes, and API key were kept." } } label: { Label("Profiles", systemImage: "square.and.arrow.up") }.menuStyle(.borderlessButton).fixedSize()
                Button("Show notch") { model.onPreviewNotch?() }.buttonStyle(.bordered)
            }
            preview
            HStack(spacing: 9) {
                ForEach(["Default", "Minimal", "Studio", "Focus", "Island"], id: \.self) { name in
                    Button { model.notch = NotchConfiguration.preset(name); model.onPreviewNotch?() } label: {
                        HStack(spacing: 7) { Circle().fill(NotchConfiguration.preset(name).tint).frame(width: 7, height: 7); Text(name).font(.system(size: 11, weight: .medium)) }.padding(.horizontal, 13).padding(.vertical, 9).background(card, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("PRESETS").font(.system(size: 8, design: .monospaced)).tracking(1.5).foregroundStyle(.gray)
            }
            if let message { Text(message).font(.system(size: 12)).foregroundStyle(tint).textSelection(.enabled) }
            Picker("Customize", selection: $tab) {
                ForEach(["Appearance", "Layout", "Modules", "Behavior"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).labelsHidden()
            switch tab {
            case "Appearance": appearance
            case "Layout": layout
            case "Modules": modules
            default: behavior
            }
        }.tint(tint)
    }

    private var preview: some View {
        GeometryReader { proxy in
            let horizontal = model.notch.expansionLayout == .horizontal
            let width = horizontal && model.notch.fullWidthExpansion ? max(200, proxy.size.width - 28) : min(model.notch.expandedWidth, max(200, proxy.size.width - 42))
            ZStack(alignment: .top) {
                LinearGradient(colors: [tint.opacity(0.12), Color.white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 0) {
                    HStack { Text("9:41"); Spacer(); Image(systemName: "wifi"); Image(systemName: "battery.100") }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.24)).padding(.horizontal, 14).frame(height: 27)
                    Spacer()
                    HStack { Text("LIVE PREVIEW").tracking(2); Spacer(); Text(model.notch.expansionLayout == .horizontal ? "HORIZONTAL · \(Int(model.notch.horizontalHeight)) pt" : "\(Int(model.notch.expandedWidth)) × \(Int(model.notch.contentHeight)) pt") }.font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.32)).padding(14)
                }
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: model.notch.leftWing.icon)
                        Spacer()
                        if model.notch.style == .floating { Text("Newt").font(.system(size: 10)) }
                        Spacer()
                        Image(systemName: model.notch.rightWing.icon)
                    }.font(.system(size: 11)).foregroundStyle(tint).padding(.horizontal, 24).frame(height: 30)
                        .background(model.notch.style == .attached ? Color.black : .clear)
                    if horizontal {
                        VStack(spacing: 8) {
                            NotchModulesGrid(width: max(1, width - 20), model: model, speech: model.speech)
                            Divider().overlay(tint.opacity(0.12))
                            HStack {
                                Label("Newtv1", systemImage: "waveform").font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                                Spacer()
                                Text("Start listening").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 16).frame(height: 30).background(tint, in: RoundedRectangle(cornerRadius: 8))
                                Image(systemName: "stop.circle").foregroundStyle(.orange)
                                Image(systemName: "sparkles").foregroundStyle(tint)
                            }.frame(height: 30)
                        }.padding(10).allowsHitTesting(false)
                    } else {
                    HStack { Label("Newtv1", systemImage: "waveform").font(.system(size: 14, weight: .semibold)); Spacer(); Text("YOUR SPACE").font(.system(size: 7, design: .monospaced)).foregroundStyle(tint) }.padding(.horizontal, 18).padding(.vertical, 10)
                    ScrollView {
                        VStack(alignment: .leading, spacing: model.notch.compactRows ? 8 : 15) {
                            ForEach(model.notch.normalized().visibleSections) { section in NotchModule(section: section, model: model, speech: model.speech) }
                        }.padding(.horizontal, 18).padding(.bottom, 12)
                    }.allowsHitTesting(false)
                    HStack { Label("Start listening", systemImage: "mic.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).frame(maxWidth: .infinity).padding(8).background(tint, in: RoundedRectangle(cornerRadius: 7)); Image(systemName: "stop.circle").foregroundStyle(.orange); Image(systemName: "sparkles").foregroundStyle(tint) }.padding(14)
                    }
                }
                .frame(width: width)
                .frame(height: horizontal ? nil : min(280, model.notch.contentHeight + 30))
                .background(NotchSurface(config: model.notch))
                .clipShape(NotchShape(radius: model.notch.cornerRadius, floating: model.notch.style == .floating))
                .padding(.top, model.notch.style == .floating ? 38 : 0)
            }.clipShape(RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07)))
        }
        .frame(height: model.notch.expansionLayout == .horizontal ? previewHeight : model.notch.style == .floating ? 352 : 314)
        .onPreferenceChange(NotchGridMeasurementKey.self) { measurement in
            guard let measurement, model.notch.expansionLayout == .horizontal else { return }
            let height = measurement.height + 150 + (model.notch.style == .floating ? 38 : 0)
            if abs(previewHeight - height) > 1 { previewHeight = max(314, height) }
        }
    }

    private var appearance: some View {
        group("Appearance", "Keep it subtle or give it a little personality.") {
            Picker("Surface", selection: $model.notch.finish) { ForEach(NotchFinish.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
            HStack(spacing: 14) {
                Text("Accent").font(.system(size: 12)); Spacer()
                ForEach(["C9F76E", "B8A2FF", "79D5FF", "FF91B8", "FFB989", "FFFFFF"], id: \.self) { hex in
                    Button { model.notch.accentHex = hex } label: {
                        Circle().fill(color(hex)).frame(width: 23, height: 23).overlay(Circle().stroke(.white.opacity(model.notch.accentHex == hex ? 0.9 : 0), lineWidth: 2).padding(-4))
                    }.buttonStyle(.plain).help(hex)
                }
                ColorPicker("Custom color", selection: Binding(get: { tint }, set: { value in
                    if let rgb = NSColor(value).usingColorSpace(.sRGB) { model.notch.accentHex = String(format: "%02X%02X%02X", Int(round(rgb.redComponent * 255)), Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255))) }
                }), supportsOpacity: false).labelsHidden()
            }
            slider("Opacity", value: $model.notch.opacity, range: 0.65...1, format: "%.2f")
            slider("Accent border", value: $model.notch.borderOpacity, range: 0...0.65, format: "%.2f")
            slider("Corner radius", value: $model.notch.cornerRadius, range: 6...40, format: "%.0f pt")
            HStack(spacing: 22) {
                signalSample("Ready", .idle)
                signalSample("Listening", .listening)
                signalSample("Working", .working)
                Spacer()
                Text("STATUS MOTION").font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(.gray)
            }
            Toggle("Show live microphone waveform", isOn: $model.notch.showWaveform)
            Toggle("Compact module spacing", isOn: $model.notch.compactRows)
        }
    }

    private var layout: some View {
        group("Layout & placement", "Attached mode always keeps the camera cutout clear.") {
            Picker("Expansion", selection: $model.notch.expansionLayout) { Text("Horizontal bar").tag(NotchExpansionLayout.horizontal); Text("Vertical panel").tag(NotchExpansionLayout.vertical) }.pickerStyle(.segmented)
            if model.notch.expansionLayout == .horizontal {
                Toggle("Expand across the full display width", isOn: $model.notch.fullWidthExpansion)
                slider("Horizontal module row height", value: $model.notch.horizontalHeight, range: 120...260, format: "%.0f pt")
            }
            Picker("Placement", selection: $model.notch.style) { Text("Attached to notch").tag(NotchStyle.attached); Text("Floating island").tag(NotchStyle.floating) }.pickerStyle(.segmented)
            Picker("Display", selection: $model.notch.displayID) {
                Text("Automatic · prefer the hardware notch").tag("automatic")
                Text("Primary display").tag("main")
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in Text(screen.localizedName).tag(screenID(screen)) }
                if !["automatic", "main"].contains(model.notch.displayID), !NSScreen.screens.contains(where: { screenID($0) == model.notch.displayID }) { Text("Saved display · disconnected").tag(model.notch.displayID) }
            }
            if model.notch.expansionLayout == .vertical || !model.notch.fullWidthExpansion { slider("Expanded width", value: $model.notch.expandedWidth, range: 360...3200, format: "%.0f pt") }
            if model.notch.expansionLayout == .vertical { slider("Expanded content height", value: $model.notch.contentHeight, range: 220...700, format: "%.0f pt") }
            slider("Resting wing width", value: $model.notch.wingWidth, range: 32...110, format: "%.0f pt")
            if model.notch.style == .floating {
                slider("Distance below notch", value: $model.notch.floatingGap, range: 0...120, format: "%.0f pt")
                slider("Horizontal offset", value: $model.notch.horizontalOffset, range: -1000...1000, format: "%.0f pt")
            }
            HStack {
                Picker("Left wing", selection: $model.notch.leftWing) { ForEach(NotchWingAction.allCases, id: \.self) { Text($0.title).tag($0) } }
                Picker("Right wing", selection: $model.notch.rightWing) { ForEach(NotchWingAction.allCases, id: \.self) { Text($0.title).tag($0) } }
            }
        }
    }

    private var modules: some View {
        VStack(spacing: 18) {
            group("Sections", "Show what you use. Move sections up or down to set their order.") {
                ForEach(Array(model.notch.sectionOrder.enumerated()), id: \.element) { index, section in
                    HStack {
                        Image(systemName: section.icon).foregroundStyle(tint).frame(width: 20)
                        Text(section.title); Spacer()
                        Button { moveSection(index, by: -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.plain).disabled(index == 0).help("Move \(section.title) up")
                        Button { moveSection(index, by: 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.plain).disabled(index == model.notch.sectionOrder.count - 1).help("Move \(section.title) down")
                        Toggle(section.title, isOn: Binding(get: { !model.notch.hiddenSections.contains(section) }, set: { enabled in
                            model.notch.hiddenSections.removeAll { $0 == section }
                            if !enabled { model.notch.hiddenSections.append(section) }
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.font(.system(size: 12)).padding(.vertical, 3)
                }
                Text("Listening, Stop, and customization controls stay available even when every section is hidden.").font(.system(size: 11)).foregroundStyle(.gray)
            }
            group("Quick buttons", "Choose an icon and a command. Buttons follow the same execution and approval rules as typed commands.") {
                ForEach(Array(model.notch.shortcuts.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Image(systemName: NSImage(systemSymbolName: item.icon, accessibilityDescription: nil) == nil ? "bolt" : item.icon).foregroundStyle(tint).frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) { Text(item.title); Text(item.command).font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray).lineLimit(1) }
                        Spacer()
                        Button { moveShortcut(index, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                        Button { moveShortcut(index, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == model.notch.shortcuts.count - 1)
                        Button("Edit") { editingID = item.id; shortcutTitle = item.title; shortcutIcon = item.icon; shortcutCommand = item.command }
                        Button { model.notch.shortcuts.removeAll { $0.id == item.id }; if editingID == item.id { clearEditor() } } label: { Image(systemName: "trash") }
                    }.font(.system(size: 12)).buttonStyle(.borderless)
                }
                Divider()
                HStack { TextField("Button name", text: $shortcutTitle); TextField("SF Symbol · e.g. bolt", text: $shortcutIcon) }.textFieldStyle(.roundedBorder)
                TextField("Command · e.g. run focus mode", text: $shortcutCommand).textFieldStyle(.roundedBorder)
                HStack {
                    Text("Up to 8 buttons").font(.system(size: 10)).foregroundStyle(.gray)
                    Spacer()
                    if editingID != nil { Button("Cancel edit", action: clearEditor) }
                    Button(editingID == nil ? "Add button" : "Save button", action: saveShortcut).buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(editingID == nil && model.notch.shortcuts.count >= 8)
                }
            }
            group("Scratchpad", "Saved locally. This note stays on this Mac and is excluded from exported profiles.") {
                TextEditor(text: Binding(get: { model.scratchpad }, set: { model.scratchpad = String($0.prefix(16000)) })).font(.system(size: 12)).frame(height: 130).scrollContentBackground(.hidden).padding(9).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }

    private var behavior: some View {
        group("Behavior", "Choose when the notch opens and how long it stays.") {
            Toggle("Expand on hover", isOn: $model.notch.hoverToExpand)
            slider("Hover activation delay", value: $model.notch.hoverDelay, range: 0...1.5, format: "%.2f s")
            slider("Closing delay", value: $model.notch.collapseDelay, range: 0.15...5, format: "%.2f s")
            Toggle("Expand when listening starts", isOn: $model.notch.expandOnListening)
            Toggle("Expand while executing a command", isOn: $model.notch.expandOnExecution)
            Toggle("Expand when something needs attention", isOn: $model.notch.expandOnError)
            Toggle("Start pinned on the next launch", isOn: $model.notch.pinnedOnLaunch)
            Toggle("Animate changes", isOn: $model.notch.animations)
            Text("macOS Reduce Motion is respected. Timers run during this app session and do not prevent your Mac from sleeping. Use the menu-bar Customize Notch action if you turn off hover expansion.").font(.system(size: 11)).foregroundStyle(.gray)
        }
    }

    private func group<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 17, weight: .medium))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.gray).lineSpacing(3)
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(card, in: RoundedRectangle(cornerRadius: 14)).font(.system(size: 12)).toggleStyle(.switch)
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(spacing: 7) { HStack { Text(title); Spacer(); Text(String(format: format, value.wrappedValue)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray) }; Slider(value: value, in: range) }
    }
    private func color(_ hex: String) -> Color { var config = model.notch; config.accentHex = hex; return config.tint }
    private func signalSample(_ title: String, _ state: NewtSignalState) -> some View {
        HStack(spacing: 6) {
            NewtSignal(state: state, level: 0.55, tint: tint, animated: model.notch.animations).frame(width: 34, height: 34)
            Text(title).font(.system(size: 10)).foregroundStyle(.gray)
        }
    }
    private func screenID(_ screen: NSScreen) -> String { String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }
    private func moveSection(_ index: Int, by delta: Int) { let other = index + delta; guard model.notch.sectionOrder.indices.contains(other) else { return }; model.notch.sectionOrder.swapAt(index, other) }
    private func moveShortcut(_ index: Int, by delta: Int) { let other = index + delta; guard model.notch.shortcuts.indices.contains(other) else { return }; model.notch.shortcuts.swapAt(index, other) }
    private func clearEditor() { editingID = nil; shortcutTitle = ""; shortcutIcon = "bolt"; shortcutCommand = "" }
    private func saveShortcut() {
        do {
            guard !shortcutTitle.trimmingCharacters(in: .whitespaces).isEmpty, shortcutTitle.count <= 40 else { throw Newtv1Failure("Use a button name between 1 and 40 characters.") }
            guard shortcutCommand.count <= 4000 else { throw Newtv1Failure("The button command is too long.") }
            let plan = try CommandParser().parse(shortcutCommand)
            _ = try WorkflowResolver().expand(plan, workflows: model.workflows)
            let item = NotchShortcut(id: editingID ?? UUID(), title: shortcutTitle, icon: shortcutIcon, command: shortcutCommand)
            if let index = model.notch.shortcuts.firstIndex(where: { $0.id == item.id }) { model.notch.shortcuts[index] = item }
            else if model.notch.shortcuts.count < 8 { model.notch.shortcuts.append(item) }
            clearEditor(); message = "Quick button saved."
        } catch { message = error.localizedDescription }
    }
    private func exportProfile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Newtv1-notch.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(model.notch.normalized()).write(to: url, options: .atomic); message = "Profile exported. Keys, notes, and workflows are excluded; custom button commands are included." }
        catch { message = error.localizedDescription }
    }
    private func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 128_000 else { throw Newtv1Failure("Notch profiles must be smaller than 128 KB.") }
            model.notch = try NotchConfiguration.profile(Data(contentsOf: url))
            message = "Profile loaded. Imported buttons do not run until clicked; review their commands in Modules."
            model.onPreviewNotch?()
        } catch { message = "Could not import profile: \(error.localizedDescription)" }
    }
}

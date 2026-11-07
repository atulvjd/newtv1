import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Newtv1Core

private typealias UtilityState<T> = SwiftUI.State<T>

struct CalendarModule: View {
    @ObservedObject var calendar: CalendarStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if calendar.enabled {
                if calendar.events.isEmpty { Text(calendar.message).font(.system(size: 10)).foregroundStyle(.gray) }
                ForEach(calendar.events.prefix(4)) { event in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) { Text(event.title).font(.system(size: 11, weight: .medium)).lineLimit(2); Text(event.calendar).font(.system(size: 9)).foregroundStyle(.gray) }
                        Spacer()
                        if event.allDay { Text("All day").font(.system(size: 9)).foregroundStyle(.gray) }
                        else { Text(event.start, style: .time).font(.system(size: 10)).monospacedDigit() }
                    }
                }
                Menu("Calendars") {
                    Button("All calendars") { calendar.selected = [] }
                    ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                        Toggle(item.title, isOn: Binding(get: { calendar.selected.isEmpty || calendar.selected.contains(item.calendarIdentifier) }, set: { selected in
                            var ids = calendar.selected.isEmpty ? Set(calendar.calendars.map(\.calendarIdentifier)) : calendar.selected
                            if selected { ids.insert(item.calendarIdentifier) } else { ids.remove(item.calendarIdentifier) }
                            // An explicit none selection must not mean all.
                            calendar.selected = ids.isEmpty ? ["none"] : ids
                        }))
                    }
                    Divider(); Button("Disconnect") { calendar.disconnect() }
                }.menuStyle(.borderlessButton).font(.system(size: 10)).fixedSize()
            } else {
                Text(calendar.message).font(.system(size: 10)).foregroundStyle(.gray)
                Button("Connect Calendar") { calendar.connect() }.font(.system(size: 11)).buttonStyle(.plain)
            }
        }
    }
}
struct FileShelfModule: View {
    @ObservedObject var files: FileStore
    @UtilityState private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if files.shelf.isEmpty { Text("Drop files here to keep them within reach.").font(.system(size: 11)).foregroundStyle(.gray) }
            ForEach(files.shelf, id: \.path) { url in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                    Button(url.lastPathComponent) { files.reveal(url) }.lineLimit(1).onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                    Spacer(minLength: 0)
                    Button { files.remove(url) } label: { Image(systemName: "xmark") }.help("Remove from shelf; file stays on disk")
                }.buttonStyle(.plain).font(.system(size: 10))
            }
            Button("Add files…") { files.chooseFiles() }.font(.system(size: 10)).buttonStyle(.plain)
        }.frame(maxWidth: .infinity, minHeight: 55, alignment: .topLeading)
            .padding(5).background(targeted ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                for provider in providers.prefix(30) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in guard let url else { return }; Task { @MainActor in files.add([url]) } }
                }
                return !providers.isEmpty
            }
    }
}
struct DownloadsModule: View {
    @ObservedObject var files: FileStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let folder = files.folder {
                HStack { Text(folder.lastPathComponent).font(.system(size: 10)).foregroundStyle(.gray); Spacer(); Menu { Button("Change folder…") { files.chooseDownloads() }; Button("Disconnect") { files.disconnectDownloads() } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize() }
                ForEach(files.downloads.prefix(5)) { item in
                    Button { files.reveal(item.url) } label: {
                        HStack { Image(systemName: item.incomplete ? "arrow.down.circle" : "doc"); VStack(alignment: .leading) { Text(item.url.lastPathComponent).lineLimit(1); Text(item.incomplete ? "Downloading · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)) received" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)).foregroundStyle(.gray) }; Spacer(minLength: 0) }
                    }.buttonStyle(.plain).font(.system(size: 10))
                }
                if !files.message.isEmpty { Text(files.message).font(.system(size: 10)).foregroundStyle(.gray) }
            } else {
                Text("See recent files and partial downloads from a folder you choose.").font(.system(size: 10)).foregroundStyle(.gray)
                Button("Choose downloads folder…") { files.chooseDownloads() }.font(.system(size: 10)).buttonStyle(.plain)
            }
        }
    }
}
struct SystemModule: View {
    @ObservedObject var monitor: SystemMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text("CPU"); Spacer(); Text("\(Int(monitor.cpu * 100))%") }.font(.system(size: 11)).monospacedDigit()
            GeometryReader { proxy in
                Path { path in for (i, value) in monitor.history.enumerated() { let point = CGPoint(x: Double(i) / 59 * proxy.size.width, y: (1 - value) * proxy.size.height); if i == 0 { path.move(to: point) } else { path.addLine(to: point) } } }.stroke(.green, lineWidth: 1.5)
            }.frame(height: 25)
            HStack { Text("Memory in use"); Spacer(); Text("\(Int(monitor.memory * 100))%") }.font(.system(size: 10)).foregroundStyle(.gray)
            Text("\(ByteCountFormatter.string(fromByteCount: monitor.diskFree, countStyle: .file)) disk free · \(monitor.battery)").font(.system(size: 9)).foregroundStyle(.gray)
        }
    }
}
struct InboxModule: View {
    @ObservedObject var notices: NoticeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if notices.notices.isEmpty { Text("Newt’s timer, task, and routine updates appear here.").font(.system(size: 10)).foregroundStyle(.gray) }
            ForEach(notices.notices.prefix(5)) { notice in
                VStack(alignment: .leading, spacing: 3) { Text(notice.title).font(.system(size: 11, weight: notice.read ? .regular : .semibold)); Text(notice.detail).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(2); Text(notice.date, style: .time).font(.system(size: 9)).foregroundStyle(.gray) }
            }
            if !notices.notices.isEmpty { HStack { Button("Mark read") { notices.markRead() }; Button("Clear") { notices.clear() } }.buttonStyle(.plain).font(.system(size: 10)) }
        }
    }
}
struct ClipboardModule: View {
    @ObservedObject var clipboard: ClipboardStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Clipboard history", isOn: $clipboard.enabled).font(.system(size: 11)).toggleStyle(.switch).controlSize(.mini)
            if clipboard.enabled {
                Text("Session only. Copied private text may be included; pause before copying secrets.").font(.system(size: 9)).foregroundStyle(.gray)
                ForEach(clipboard.entries.prefix(5)) { entry in Button { clipboard.copy(entry) } label: { Text(entry.label).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 10)).buttonStyle(.plain).help("Copy again") }
                Button("Clear history") { clipboard.clear() }.font(.system(size: 10)).buttonStyle(.plain)
            } else { Text("Off by default. Enable to keep the last 20 text, image, or file copies in memory.").font(.system(size: 10)).foregroundStyle(.gray) }
        }
    }
}
struct RoutineModule: View {
    @ObservedObject var routines: RoutineStore
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(routines.routines.filter { $0.awaitingReview }.prefix(3)) { routine in Button("Review: " + routine.name) { model.reviewRoutine(routine) }.font(.system(size: 11)).buttonStyle(.plain) }
            if let next = routines.routines.filter({ $0.enabled && !$0.awaitingReview }).min(by: { $0.nextRun < $1.nextRun }) { Text("Next: \(next.name)").font(.system(size: 11)); Text(next.nextRun, style: .relative).font(.system(size: 10)).foregroundStyle(.gray) }
            Button("Manage routines ↗") { model.openCommandCenter(page: .routines) }.font(.system(size: 10)).buttonStyle(.plain)
        }
    }
}

struct RoutinesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: RoutineStore
    @UtilityState private var name = ""
    @UtilityState private var commands = ""
    @UtilityState private var date = Date().addingTimeInterval(3600)
    @UtilityState private var repetition = ScheduledRoutine.Repetition.once
    @UtilityState private var editing: UUID?
    @UtilityState private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Routines, right on time.").font(.system(size: 29, weight: .semibold))
            Text("Schedules are saved on this Mac. Newtv1 must be open; missed runs become one review when it returns. Every run requires review before any action starts.").font(.system(size: 12)).foregroundStyle(.gray)
            ForEach(store.routines) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(item.name).font(.system(size: 16, weight: .medium)); Spacer(); Toggle("Enabled", isOn: Binding(get: { store.routines.first(where: { $0.id == item.id })?.enabled ?? false }, set: { value in if let i = store.routines.firstIndex(where: { $0.id == item.id }) { store.routines[i].enabled = value } })).fixedSize() }
                    Text(item.awaitingReview ? "Ready for review" : item.nextRun.formatted() + " · " + item.repetition.rawValue).font(.system(size: 11)).foregroundStyle(model.notch.tint)
                    Text(item.commands).font(.system(size: 11, design: .monospaced)).foregroundStyle(.gray)
                    HStack {
                        if item.awaitingReview { Button("Review run") { model.reviewRoutine(item) }; Button("Skip occurrence") { store.dismiss(item.id) } }
                        Button("Edit") { editing = item.id; name = item.name; commands = item.commands; date = item.nextRun; repetition = item.repetition }
                        Button("Delete schedule") { store.routines.removeAll { $0.id == item.id } }
                    }.buttonStyle(.bordered)
                }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(editing == nil ? "New routine" : "Edit routine").font(.system(size: 17, weight: .medium))
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                TextEditor(text: $commands).font(.system(size: 12, design: .monospaced)).frame(height: 120)
                Text("One supported command per line. You can use run WORKFLOW NAME.").font(.system(size: 10)).foregroundStyle(.gray)
                DatePicker("First run", selection: $date)
                Picker("Repeat", selection: $repetition) { ForEach(ScheduledRoutine.Repetition.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                HStack {
                    Button("Save routine") { save() }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                    if editing != nil { Button("Cancel edit") { editing = nil; name = ""; commands = "" } }
                    Menu("Use workflow") { ForEach(model.workflows) { workflow in Button(workflow.name) { name = workflow.name; commands = "run " + workflow.name } } }
                }
                if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(.orange) }
            }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private func save() {
        do {
            var item = ScheduledRoutine(id: editing ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), commands: commands, nextRun: date, repetition: repetition)
            _ = try item.plan(workflows: model.workflows)
            guard date > Date() else { throw Newtv1Failure("Choose a future time.") }
            guard editing != nil || store.routines.count < 50 else { throw Newtv1Failure("Keep up to 50 schedules.") }
            if let i = store.routines.firstIndex(where: { $0.id == item.id }) { item.enabled = store.routines[i].enabled; store.routines[i] = item } else { store.routines.append(item) }
            editing = nil; name = ""; commands = ""; message = "Routine saved."
        } catch { message = error.localizedDescription }
    }
}

struct UtilitiesView: View {
    @ObservedObject var model: AppModel
    @UtilityState private var snippetName = ""
    @UtilityState private var snippetText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your everyday tools.").font(.system(size: 29, weight: .semibold))
            Text("Modules also live in the notch. Connect only the sources you want.").font(.system(size: 12)).foregroundStyle(.gray)
            utilityCard("Audio output", icon: "speaker.wave.2") { AudioModule(audio: model.audio) }
            utilityCard("Calendar", icon: "calendar") { CalendarModule(calendar: model.calendar) }
            utilityCard("Downloads", icon: "arrow.down.circle") { DownloadsModule(files: model.files) }
            utilityCard("File shelf", icon: "tray") { FileShelfModule(files: model.files) }
            utilityCard("System monitor", icon: "gauge.with.dots.needle.50percent") { SystemModule(monitor: model.monitor) }
            utilityCard("Camera mirror", icon: "camera") { CameraModule(camera: model.camera) }
            utilityCard("Clipboard", icon: "doc.on.clipboard") { ClipboardModule(clipboard: model.clipboard) }
            SnippetsView(clipboard: model.clipboard)
            utilityCard("Newt inbox", icon: "bell") { InboxModule(notices: model.notices) }
        }
    }
    private func utilityCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Label(title, systemImage: icon).font(.system(size: 17, weight: .medium)); content() }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct SnippetsView: View {
    @ObservedObject var clipboard: ClipboardStore
    @UtilityState private var name = ""
    @UtilityState private var text = ""
    @UtilityState private var edit: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Text snippets", systemImage: "text.badge.plus").font(.system(size: 17, weight: .medium))
            ForEach(clipboard.snippets) { snippet in
                HStack { Button(snippet.name) { clipboard.copyText(expanded(snippet.text)) }.buttonStyle(.plain); Spacer(); Button("Edit") { edit = snippet.id; name = snippet.name; text = snippet.text }; Button("Remove") { clipboard.snippets.removeAll { $0.id == snippet.id } } }.font(.system(size: 12))
            }
            TextField("Snippet name", text: $name).textFieldStyle(.roundedBorder)
            TextEditor(text: $text).frame(height: 80)
            Text("Click a saved snippet to copy it. {{date}} and {{time}} expand when copied.").font(.system(size: 10)).foregroundStyle(.gray)
            HStack { Button(edit == nil ? "Save snippet" : "Update snippet") {
                let snippet = ClipboardStore.Snippet(id: edit ?? UUID(), name: String(name.prefix(80)), text: String(text.prefix(16000)))
                if let i = clipboard.snippets.firstIndex(where: { $0.id == snippet.id }) { clipboard.snippets[i] = snippet } else { clipboard.snippets.append(snippet) }
                edit = nil; name = ""; text = ""
            }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || text.isEmpty || (edit == nil && clipboard.snippets.count >= 100))
                if edit != nil { Button("Cancel") { edit = nil; name = ""; text = "" } }
            }
        }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
    private func expanded(_ value: String) -> String { value.replacingOccurrences(of: "{{date}}", with: Date().formatted(date: .abbreviated, time: .omitted)).replacingOccurrences(of: "{{time}}", with: Date().formatted(date: .omitted, time: .shortened)) }
}

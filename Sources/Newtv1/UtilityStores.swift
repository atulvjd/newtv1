import AppKit
import EventKit
import SwiftUI
import UniformTypeIdentifiers
import IOKit.ps
import Darwin
import Newtv1Core

@MainActor
final class RoutineStore: ObservableObject {
    @Published var routines: [ScheduledRoutine] { didSet { save() } }
    init() { routines = UserDefaults.standard.data(forKey: "scheduledRoutines").flatMap { try? JSONDecoder().decode([ScheduledRoutine].self, from: $0) } ?? [] }
    func save() { if let data = try? JSONEncoder().encode(routines) { UserDefaults.standard.set(data, forKey: "scheduledRoutines") } }
    func tick(now: Date = Date()) -> [String] {
        var copy = routines
        var triggered: [String] = []
        for i in copy.indices where copy[i].enabled && !copy[i].awaitingReview && copy[i].nextRun <= now {
            copy[i].trigger(at: now); triggered.append(copy[i].name)
        }
        if !triggered.isEmpty { routines = copy }
        return triggered
    }
    func dismiss(_ id: UUID) { if let i = routines.firstIndex(where: { $0.id == id }) { routines[i].awaitingReview = false } }
}

struct NewtNotice: Codable, Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let date: Date
    var read: Bool
}
@MainActor
final class NoticeStore: ObservableObject {
    @Published private(set) var notices: [NewtNotice]
    init() { notices = UserDefaults.standard.data(forKey: "newtNotices").flatMap { try? JSONDecoder().decode([NewtNotice].self, from: $0) } ?? [] }
    func add(_ title: String, detail: String) {
        notices.insert(NewtNotice(id: UUID(), title: String(title.prefix(100)), detail: String(detail.prefix(500)), date: Date(), read: false), at: 0)
        notices = Array(notices.prefix(50)); save()
    }
    func markRead() { for i in notices.indices { notices[i].read = true }; save() }
    func clear() { notices = []; save() }
    private func save() { if let data = try? JSONEncoder().encode(notices) { UserDefaults.standard.set(data, forKey: "newtNotices") } }
}

@MainActor
final class CalendarStore: ObservableObject {
    struct Event: Identifiable { let id: String; let title: String; let start: Date; let end: Date; let calendar: String; let allDay: Bool }
    private let store = EKEventStore()
    @Published private(set) var events: [Event] = []
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var message = "Connect Calendar to see upcoming events."
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "calendarEnabled")
    @Published var selected: Set<String> { didSet { UserDefaults.standard.set(Array(selected), forKey: "calendarSelection"); refresh() } }
    init() { selected = Set(UserDefaults.standard.stringArray(forKey: "calendarSelection") ?? []) }
    func connect() {
        Task {
            do {
                let allowed: Bool
                if #available(macOS 14, *) { allowed = try await store.requestFullAccessToEvents() }
                else { allowed = try await store.requestAccess(to: .event) }
                enabled = allowed; UserDefaults.standard.set(allowed, forKey: "calendarEnabled")
                message = allowed ? "No events in the next 24 hours." : "Calendar access is off. Enable it in Privacy & Security → Calendars."
                refresh()
            } catch { message = error.localizedDescription }
        }
    }
    func disconnect() { enabled = false; UserDefaults.standard.set(false, forKey: "calendarEnabled"); events = []; calendars = []; message = "Calendar disconnected." }
    func refresh() {
        guard enabled else { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        let authorized: Bool
        if #available(macOS 14, *) { authorized = status == .fullAccess } else { authorized = status == .authorized }
        guard authorized else { events = []; message = "Reconnect Calendar after granting access in System Settings."; return }
        calendars = store.calendars(for: .event)
        let chosen = calendars.filter { selected.isEmpty || selected.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { events = []; message = "Selected calendars are unavailable. Choose another calendar."; return }
        let now = Date()
        events = store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(86400), calendars: chosen))
            .filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }.prefix(20).map {
                Event(id: ($0.calendarItemIdentifier) + String($0.startDate.timeIntervalSince1970), title: $0.title ?? "Untitled event", start: $0.startDate, end: $0.endDate, calendar: $0.calendar.title, allDay: $0.isAllDay)
            }
        message = "No events in the next 24 hours."
    }
}

@MainActor
final class FileStore: ObservableObject {
    struct Item: Identifiable { var id: String { url.path }; let url: URL; let size: Int64; let modified: Date; let incomplete: Bool }
    @Published private(set) var shelf: [URL] = []
    @Published private(set) var downloads: [Item] = []
    @Published private(set) var folder: URL?
    @Published var message = ""
    private var scopes: [URL] = []
    init() {
        for data in UserDefaults.standard.array(forKey: "shelfBookmarks") as? [Data] ?? [] {
            if let url = resolve(data) { shelf.append(url) }
        }
        if let data = UserDefaults.standard.data(forKey: "downloadBookmark") { folder = resolve(data) }
    }
    private func resolve(_ data: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale) else { return nil }
        if url.startAccessingSecurityScopedResource() { scopes.append(url) }
        return url
    }
    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !shelf.contains(url) && shelf.count < 30 { shelf.append(url) }
        persistShelf()
    }
    func chooseFiles() { let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true; if panel.runModal() == .OK { add(panel.urls) } }
    func remove(_ url: URL) { shelf.removeAll { $0 == url }; persistShelf() }
    private func persistShelf() {
        let data = shelf.compactMap { try? $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
        UserDefaults.standard.set(data, forKey: "shelfBookmarks")
    }
    func chooseDownloads() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.message = "Choose the downloads folder to monitor. Newtv1 reads filenames, sizes, and modification dates."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "downloadBookmark"); folder = url; refresh()
        } catch { message = error.localizedDescription }
    }
    func disconnectDownloads() { folder = nil; downloads = []; UserDefaults.standard.removeObject(forKey: "downloadBookmark") }
    func refresh() {
        guard let folder else { return }
        do {
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            downloads = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]).prefix(1000).compactMap { url -> Item? in
                let v = try url.resourceValues(forKeys: keys)
                let partial = ["download", "crdownload", "part", "partial"].contains(url.pathExtension.lowercased())
                guard v.isRegularFile == true || partial else { return nil }
                return Item(url: url, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate ?? .distantPast, incomplete: partial)
            }.sorted { $0.modified > $1.modified }.prefix(20).map { $0 }
            message = downloads.isEmpty ? "No files in the selected folder." : ""
        } catch { downloads = []; message = "Folder unavailable. Select it again to restore access." }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu = 0.0
    @Published private(set) var memory = 0.0
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var battery = "Desktop power"
    @Published private(set) var history: [Double] = []
    private var previous: [UInt32]?
    func refresh() {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) } }
        if result == KERN_SUCCESS {
            let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
            if let previous {
                let delta = zip(ticks, previous).map { Double($0 &- $1) }; let total = delta.reduce(0,+)
                cpu = total > 0 ? max(0, min(1, 1 - delta[2] / total)) : 0
                history.append(cpu); history = Array(history.suffix(60))
            }
            previous = ticks
        }
        var vm = vm_statistics64(); var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { pointer in pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(host, HOST_VM_INFO64, $0, &vmCount) } }
        if vmResult == KERN_SUCCESS { memory = min(1, Double(UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * Double(vm_kernel_page_size) / Double(ProcessInfo.processInfo.physicalMemory)) }
        diskFree = Int64((try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0)
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let current = description[kIOPSCurrentCapacityKey] as? Int, let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
                battery = "\(current * 100 / max)% · \(description[kIOPSIsChargingKey] as? Bool == true ? "Charging" : "Battery")"
            }
        }
    }
}

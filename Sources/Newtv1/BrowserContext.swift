import SwiftUI
import AppKit
import Newtv1Core

@MainActor
final class BrowserContext: ObservableObject {
    @Published private(set) var page: BrowserPage?
    @Published var approved = false
    @Published var message = "Capture a page with the Newtv1 browser extension, then load its preview here."
    private var inbox: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Newtv1/BrowserInbox/page.json") }
    func load() {
        approved = false; page = nil
        do {
            let size = try inbox.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 200_000 else { throw Newtv1Failure("Browser context is too large.") }
            page = try BrowserPage.decode(Data(contentsOf: inbox))
            message = "Review the page text. Nothing has been sent to AI."
        } catch { message = error.localizedDescription }
    }
    func consume() throws -> BrowserPage {
        guard approved, let page else { throw Newtv1Failure("Review this page and approve it for one request first.") }
        approved = false
        return try page.validated()
    }
    func clear() {
        approved = false; page = nil
        if FileManager.default.fileExists(atPath: inbox.path) {
            do { try FileManager.default.removeItem(at: inbox); message = "Browser preview removed from Newtv1." }
            catch { message = "Could not remove the saved browser preview." }
        }
    }
}
private typealias BrowserViewState<T> = SwiftUI.State<T>

struct BrowserContextView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var browser: BrowserContext
    @BrowserViewState private var question = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceHeading(title: "A helping hand in your browser.", subtitle: "Connect a tab for a task, or bring a page into the conversation. You choose what to share.")
            BrowserAgentView(model: model, agent: model.browserAgent)
            HStack { Button("Load browser preview") { browser.load() }; Button("Clear preview") { browser.clear() } }.buttonStyle(WorkspaceButtonStyle())
            Text(browser.message).font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary)
            if let page = browser.page {
                VStack(alignment: .leading, spacing: 12) {
                    Text(page.title).font(.system(size: 20, weight: .medium))
                    Text(page.url).font(.system(size: 11)).foregroundStyle(WorkspaceTheme.accent).textSelection(.enabled)
                    Text("Captured \(page.capturedAt.formatted()) · expires after 15 minutes").font(.system(size: 10)).foregroundStyle(WorkspaceTheme.secondary)
                    ScrollView { Text(page.text).font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 240)
                    Toggle("Use this preview for one \(model.aiProvider.title) request", isOn: $browser.approved).toggleStyle(WorkspaceToggleStyle())
                    TextField("Ask about this page…", text: $question).textFieldStyle(WorkspaceFieldStyle())
                    Button("Ask Newt") {
                        do { let page = try browser.consume(); model.requestBrain(question, mode: .answer, browserPage: page) }
                        catch { browser.message = error.localizedDescription }
                    }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black).disabled(!browser.approved || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || model.capturingScreen || model.pending != nil)
                }.padding(20).workspaceCard()
            }
            DisclosureGroup("Browser extension setup") {
                VStack(alignment: .leading, spacing: 12) {
                Text("1. Open your browser’s Extensions page and choose Load unpacked. Select this project’s browser-extension folder.\n2. Copy the extension ID.\n3. Run the host installer below with that ID.\n4. Click the extension on a page, inspect the preview, and choose Save preview to Newtv1.").font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary).lineSpacing(5)
                Text("bash scripts/install-browser-host.sh EXTENSION_ID").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Text("Supports Chromium browsers with native messaging. Requires this locally built app to stay at its installed path. No account cookies, form values, or browser passwords are requested.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                }.padding(.top, 12)
            }.padding(20).workspaceCard()
        }
    }
}

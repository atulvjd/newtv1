import SwiftUI
import Newtv1Core
private typealias WriteState<T> = SwiftUI.State<T>

struct ServiceWriteView: View {
    @ObservedObject var connections: Connections
    @WriteState private var kind: ServiceWrite.Kind = .gmailDraft
    @WriteState private var target = ""
    @WriteState private var title = ""
    @WriteState private var content = ""
    @WriteState private var start = Date().addingTimeInterval(3600)
    @WriteState private var end = Date().addingTimeInterval(7200)
    @WriteState private var proposal: ServiceWrite?
    @WriteState private var message = ""
    var body: some View {
        DisclosureGroup("Write to a connected service") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Action", selection: $kind) { ForEach(ServiceWrite.Kind.allCases) { Text($0.rawValue).tag($0) } }
                if [.gmailDraft, .gmailSend, .slack, .notion].contains(kind) {
                    TextField(kind == .slack ? "Exact Slack channel ID" : kind == .notion ? "Exact Notion page UUID" : "Recipient email address", text: $target).textFieldStyle(WorkspaceFieldStyle())
                }
                if [.gmailDraft, .gmailSend, .calendar, .drive].contains(kind) { TextField(kind == .drive ? "Filename" : "Subject / title", text: $title).textFieldStyle(WorkspaceFieldStyle()) }
                TextEditor(text: $content).font(.system(size: 12)).frame(height: 100)
                if kind == .calendar { DatePicker("Starts", selection: $start); DatePicker("Ends", selection: $end); Text("Creates an event in the connected account's primary calendar, without inviting attendees.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary) }
                Text("Google writes require reconnecting with the write-permissions switch enabled. Slack needs chat:write and channel membership. Notion needs Insert content on the selected page. This form sends the reviewed content to the named service, without using AI.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                Button("Review action") {
                    do {
                        let draft = ServiceWrite(kind: kind, target: target, title: title, text: content, start: start, end: end)
                        _ = try draft.request(token: "validation-only"); proposal = draft; message = ""
                    } catch { message = error.localizedDescription }
                }.buttonStyle(WorkspaceButtonStyle()).disabled(connections.busy)
                if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(.orange) }
                if let proposal {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(proposal.kind.rawValue).font(.system(size: 17, weight: .semibold))
                        Text("Connected account: " + proposal.kind.account + " · target: " + (proposal.target.isEmpty ? "connected account" : proposal.target)).font(.system(size: 12)).textSelection(.enabled)
                        Text(proposal.title).font(.system(size: 14, weight: .medium)).textSelection(.enabled)
                        Text(proposal.text).font(.system(size: 12)).textSelection(.enabled)
                        if proposal.kind == .calendar { Text(proposal.start.formatted() + " → " + proposal.end.formatted() + " · " + TimeZone.current.identifier).font(.system(size: 12)) }
                        HStack {
                            Button("Confirm: " + proposal.kind.rawValue) { self.proposal = nil; connections.perform(proposal) }.buttonStyle(WorkspaceButtonStyle(primary: true))
                            Button("Cancel") { self.proposal = nil }.buttonStyle(WorkspaceButtonStyle())
                        }.disabled(connections.busy)
                    }.padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(.top, 10)
        }
    }
}

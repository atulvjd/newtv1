import SwiftUI
import Newtv1Core

struct ChatGPTSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var connection: ChatGPTConnection
    private var changingAccountBlocked: Bool { model.busy || model.capturingScreen || model.pending != nil || model.speech.isListening }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Bring your ChatGPT plan.").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("Connect an eligible Plus or Pro account for answers, planning, and approved screen questions. No API key to paste.")
                        .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary).lineSpacing(3)
                }
                Spacer()
                Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 25, weight: .light)).foregroundStyle(WorkspaceTheme.accent)
            }
            if !connection.accounts.isEmpty {
                Picker("ChatGPT account", selection: Binding(get: { connection.activeID ?? "" }, set: { id in model.stop(); connection.select(id) })) {
                    if connection.activeID == nil { Text("Choose an account").tag("") }
                    ForEach(connection.accounts) { account in Text(account.label + (account.session == nil ? " · signed out" : "")).tag(account.id) }
                }.disabled(connection.busy || changingAccountBlocked)
            }
            HStack(spacing: 10) {
                if connection.busy {
                    ProgressView().controlSize(.small)
                    Button("Cancel connection") { connection.cancel() }.buttonStyle(WorkspaceButtonStyle())
                } else {
                    Button("Continue with ChatGPT") { model.stop(); connection.connect() }.buttonStyle(WorkspaceButtonStyle(primary: true)).disabled(changingAccountBlocked)
                    if connection.active != nil {
                        Button("Reconnect account") { model.stop(); connection.connect(reconnect: true) }.buttonStyle(WorkspaceButtonStyle()).disabled(changingAccountBlocked)
                    }
                    if connection.active?.session != nil {
                        Button("Sign out") { model.stop(); connection.signOut() }.buttonStyle(.plain).foregroundStyle(WorkspaceTheme.secondary).disabled(changingAccountBlocked)
                    }
                }
            }
            Text(connection.message).font(.system(size: 12)).foregroundStyle(connection.connected ? WorkspaceTheme.accent : WorkspaceTheme.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if connection.connected {
                HStack {
                    Picker("Model", selection: $connection.selectedModel) {
                        if connection.models.isEmpty { Text(connection.selectedModel.isEmpty ? "Refresh models to choose" : connection.selectedModel).tag(connection.selectedModel) }
                        ForEach(connection.models) { item in Text(item.name).tag(item.id) }
                    }.disabled(connection.models.isEmpty || connection.busy || changingAccountBlocked)
                    Button("Refresh models") { connection.refreshModels() }.buttonStyle(WorkspaceButtonStyle()).disabled(connection.busy || changingAccountBlocked)
                }
            }
            HStack {
                Link("Manage app usage in ChatGPT", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                Spacer()
                Link("How sign-in works", destination: URL(string: "https://developers.openai.com/siwc/token-sharing-open-source")!)
            }.font(.system(size: 11))
            Text("Plan limits and available models depend on your account. This does not import your ChatGPT conversations. Audio transcription is unavailable through this connection; voice commands use Apple recognition. Newtv1 keeps action reviews and one-time screenshot sharing.")
                .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary).lineSpacing(4)
        }.padding(22).workspaceCard()
            .onAppear {
                do { try connection.load(); if connection.connected, connection.models.isEmpty { connection.refreshModels() } }
                catch { model.error = error.localizedDescription }
            }
    }
}

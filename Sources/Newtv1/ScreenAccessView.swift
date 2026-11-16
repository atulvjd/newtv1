import SwiftUI
import AppKit
import Newtv1Core

private typealias ScreenViewState<T> = SwiftUI.State<T>

struct ScreenAccessView: View {
    @ObservedObject var model: AppModel
    var suggestedQuestion = ""
    @ScreenViewState private var allowed = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("What’s on your screen", systemImage: "viewfinder").font(.system(size: 17, weight: .medium))
                Spacer()
                Label(allowed ? "Access allowed" : "Needs Screen Recording", systemImage: allowed ? "checkmark.circle" : "lock")
                    .font(.system(size: 11)).foregroundStyle(allowed ? WorkspaceTheme.accent : .orange)
            }
            Text("Capture a fresh preview, read its text on this Mac, or share it once for a visual answer. Newtv1’s own windows are excluded. Previews expire after two minutes.")
                .font(.system(size: 12)).foregroundStyle(WorkspaceTheme.secondary).lineSpacing(4)
            HStack {
                Picker("Display", selection: $model.screenDisplayChoice) {
                    Text("Display under pointer").tag("pointer")
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { _, screen in Text(screen.localizedName).tag(String(ScreenContext.id(screen))) }
                }
                if !allowed { Button("Allow screen access") { model.openPrivacy("ScreenCapture") }.buttonStyle(WorkspaceButtonStyle()) }
            }
            HStack(spacing: 10) {
                Button { prepareQuestion(); model.captureScreenForReview() } label: { Label(model.capturingScreen ? "Preparing…" : "Capture preview", systemImage: "display") }.buttonStyle(WorkspaceButtonStyle())
                Button("Read screen text locally") { model.captureScreenForReview(readText: true) }.buttonStyle(WorkspaceButtonStyle())
                Spacer(minLength: 0)
                if model.capturedScreen != nil { Button("Discard") { model.clearScreenContext() }.buttonStyle(.plain).foregroundStyle(WorkspaceTheme.secondary) }
            }.disabled(model.capturingScreen || model.busy || model.pending != nil)
            if let screen = model.capturedScreen {
                if let image = screen.preview {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 290)
                        .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Local preview of \(screen.displayName)")
                }
                Text("\(screen.displayName) · captured \(screen.capturedAt.formatted(date: .omitted, time: .shortened)) · not shared yet")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
                TextField("What would you like to know about this screen?", text: $model.guideQuestion).textFieldStyle(WorkspaceFieldStyle())
                HStack {
                    Button("Share once with \(model.aiProvider.title)") {
                        model.approvedScreenID = screen.id
                        model.askUsingApprovedScreen()
                    }.buttonStyle(WorkspaceButtonStyle(primary: true))
                        .disabled(model.busy || model.capturingScreen || model.pending != nil || model.guideQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Read preview text locally") { model.readScreenLocally() }.buttonStyle(WorkspaceButtonStyle()).disabled(model.busy || model.capturingScreen)
                }
                Text("Sharing sends this screenshot and your question to \(model.aiProvider.title). Check for private content first. Each capture needs a new approval.")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
            }
            if !model.localScreenText.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Text read on this Mac", systemImage: "text.viewfinder").font(.system(size: 13, weight: .medium)).foregroundStyle(WorkspaceTheme.accent)
                    ScrollView { Text(model.localScreenText).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 200)
                }.padding(16).background(WorkspaceTheme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Try “Newt, read my screen” or “Newt, what’s on my screen?”").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary)
        }.padding(24).workspaceCard()
            .onAppear { allowed = CGPreflightScreenCaptureAccess() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in allowed = CGPreflightScreenCaptureAccess() }
    }
    private func prepareQuestion() {
        if !suggestedQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.guideQuestion = suggestedQuestion }
        else if model.guideQuestion.isEmpty { model.guideQuestion = "Describe what is visible on my screen." }
    }
}

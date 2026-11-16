import SwiftUI
import Newtv1Core

// Explicitly reference the property wrapper type: newer SDKs also export a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private let accent = WorkspaceTheme.accent
private let surface = WorkspaceTheme.card
private let muted = WorkspaceTheme.secondary

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    @ViewState private var newWorkflow = false
    @ViewState private var editingWorkflow: Workflow?
    @ViewState private var apiKey = ""
    @ViewState private var keyMessage: String?
    @ViewState private var navigationSearch = ""
    @ViewState private var settingsTab = "Voice"

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let error = model.error {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                Text(error).font(.system(size: 13)).textSelection(.enabled)
                                Spacer()
                                if model.accessibilityIssue { Button("Set up access") { model.openCommandCenter(page: .settings) }.buttonStyle(WorkspaceButtonStyle()) }
                                Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            }.padding(15).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                        switch model.page {
                        case .diagrams: DiagramStudio(model: model)
                        case .connections: ConnectionsView(model: model, connections: model.connections)
                        case .browser: BrowserContextView(model: model, browser: model.browser)
                        case .utilities: UtilitiesView(model: model)
                        case .system: SystemControlsView(model: model, system: model.automation.system)
                        case .routines: RoutinesView(model: model, store: model.routines)
                        case .companion: CompanionView(model: model, speech: speech, speaker: model.speaker)
                        case .control: commandCenter
                        case .brain: brain
                        case .jobs: AgentJobsView(model: model)
                        case .notch: NotchStudio(model: model)
                        case .workflows: workflows
                        case .guide: guide
                        case .settings: settings
                        }
                    }.frame(maxWidth: 960, alignment: .leading).padding(32).frame(maxWidth: .infinity, alignment: .top).id("workspace-top")
                }
                .onChange(of: model.page) { _ in scroll.scrollTo("workspace-top", anchor: .top) }
                .onChange(of: settingsTab) { _ in scroll.scrollTo("workspace-top", anchor: .top) }
                }
                footer
            }
        }
        .background(WorkspaceTheme.background)
        .foregroundStyle(WorkspaceTheme.text)
        .font(.system(size: 13))
        .buttonStyle(WorkspaceButtonStyle())
        .toggleStyle(WorkspaceToggleStyle())
        .controlSize(.regular)
        .tint(accent)
        .environment(\.openURL, OpenURLAction { url in
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction
        })
        .sheet(item: $model.pending, onDismiss: { model.reviewSheetDismissed() }) { plan in confirmation(plan) }
        .sheet(isPresented: $newWorkflow) { WorkflowEditor(model: model, workflow: nil) }
        .sheet(item: $editingWorkflow) { workflow in WorkflowEditor(model: model, workflow: workflow) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 20, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 35, height: 35).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Newtv1").font(.system(size: 18, weight: .semibold, design: .rounded)).tracking(-0.6)
                    Text("A little more possible.").font(.system(size: 10)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 20).padding(.top, 37).padding(.bottom, 18)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(muted)
                TextField("Find a page", text: $navigationSearch).textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel("Find a workspace page")
                if !navigationSearch.isEmpty { Button { navigationSearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }.buttonStyle(.plain).help("Clear page search") }
            }.padding(10).background(WorkspaceTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 16).padding(.bottom, 14)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(navigationSearch.isEmpty ? ["Workspace", "Tools", "Personalize"] : ["Workspace", "Tools", "Personalize", "App"], id: \.self) { group in
                        let pages = AppPage.allCases.filter { $0.workspaceGroup == group && (navigationSearch.isEmpty || $0.workspaceTitle.localizedCaseInsensitiveContains(navigationSearch) || $0.rawValue.localizedCaseInsensitiveContains(navigationSearch)) }
                        if !pages.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.uppercased()).font(.system(size: 9, weight: .medium)).tracking(1.3).foregroundStyle(muted.opacity(0.7)).padding(.horizontal, 14).padding(.bottom, 5)
                                ForEach(pages, id: \.self) { page in navigationRow(page) }
                            }
                        }
                    }
                    if !navigationSearch.isEmpty, !AppPage.allCases.contains(where: { $0.workspaceTitle.localizedCaseInsensitiveContains(navigationSearch) || $0.rawValue.localizedCaseInsensitiveContains(navigationSearch) }) {
                        Text("No matching pages").font(.system(size: 12)).foregroundStyle(muted).padding(14)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 18)
            }.frame(maxHeight: .infinity, alignment: .top)
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach([AppPage.guide, .settings], id: \.self) { page in
                        Button { model.page = page } label: {
                            HStack(spacing: 6) { Image(systemName: page.icon); Text(page == .guide ? "Commands" : "Settings") }
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(page == model.page ? WorkspaceTheme.text : muted)
                                .frame(maxWidth: .infinity).frame(height: 29)
                                .background(page == model.page ? WorkspaceTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).help(page.workspaceTitle).accessibilityLabel(page.workspaceTitle)
                    }
                }
                Button { model.toggleListening() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: speech.isListening ? "stop.fill" : "mic").foregroundStyle(accent)
                        Text(speech.isTranscribing ? "Cancel transcription" : speech.isListening ? "Stop listening" : "Talk to Newt").font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                        Text("⌥␣").font(.system(size: 11)).foregroundStyle(muted)
                    }.padding(12).background(WorkspaceTheme.raised, in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain)
                HStack { Text("On your Mac"); Spacer(); Text("v" + model.runningVersion) }.font(.system(size: 10)).foregroundStyle(muted.opacity(0.75))
            }.padding(16).overlay(alignment: .top) { WorkspaceTheme.line.frame(height: 1) }
        }.background(WorkspaceTheme.sidebar)
    }

    private func navigationRow(_ page: AppPage) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 11) {
                Image(systemName: page.icon).font(.system(size: 13, weight: .medium)).frame(width: 18)
                Text(page.workspaceTitle).font(.system(size: 12, weight: page == model.page ? .semibold : .regular))
                Spacer()
                if page == model.page { RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3, height: 13) }
            }.foregroundStyle(page == model.page ? WorkspaceTheme.text : muted)
                .padding(.horizontal, 13).frame(height: 32)
                .background(page == model.page ? Color.white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityAddTraits(page == model.page ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(model.page.workspaceGroup).foregroundStyle(muted)
            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(muted.opacity(0.5))
            Text(model.page.workspaceTitle).fontWeight(.medium)
            Spacer(minLength: 20)
            if model.busy || speech.isListening {
                HStack(spacing: 6) { Circle().fill(accent).frame(width: 5, height: 5); Text(model.busy ? "Working" : speech.isTranscribing ? "Transcribing" : "Listening") }.font(.system(size: 11)).foregroundStyle(accent)
                Button { model.stop(); speech.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 9)).frame(width: 28, height: 28).background(WorkspaceTheme.raised, in: Circle()) }.buttonStyle(.plain).help("Stop all actions")
            } else {
                Image(systemName: "laptopcomputer").foregroundStyle(muted)
                Text("Your workspace").font(.system(size: 11)).foregroundStyle(muted)
            }
        }.font(.system(size: 12)).padding(.horizontal, 32).frame(height: 58)
            .overlay(alignment: .bottom) { WorkspaceTheme.line.frame(height: 1) }
    }

    private var commandCenter: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                WorkspaceHeading(title: "Your voice. A little superpower.", subtitle: "Move between apps, arrange windows, and make your Mac work for you.")
                Spacer()
                Label(speech.isTranscribing ? "Transcribing" : speech.isListening ? "Listening" : "Ready", systemImage: "circle.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(speech.isListening ? accent : muted).padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.04), in: Capsule())
            }
            VStack(spacing: 0) {
                HStack {
                    Label("VOICE CONTROL", systemImage: "waveform").font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(muted)
                    Spacer()
                    Text(model.allowNetwork ? "APPLE SPEECH" : "ON-DEVICE SPEECH").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                }.padding(20)
                HStack(spacing: 28) {
                    VoiceOrb(active: speech.isCapturing, level: speech.level, busy: model.busy || model.speechStarting || speech.isTranscribing, attention: model.error != nil, tint: model.notch.tint, animated: model.notch.animations).frame(width: 132, height: 132)
                    VStack(alignment: .leading, spacing: 13) {
                        Text(model.busy ? "Making it happen." : speech.isTranscribing ? "Preparing your request." : speech.isListening ? "I’m listening." : "Your voice is the shortcut.").font(.system(size: 26, weight: .medium)).tracking(-0.6)
                        Text(speech.isListening ? (model.continuousListening && model.wakeWord ? "Start with “\(model.wakePhraseLabel)”, then say a command." : "Speak your full request, then pause to send.") : "Open apps, arrange windows, click controls,\nand build routines with a few words.")
                            .font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            Button { model.toggleListening() } label: {
                                Label(model.speechStarting ? "Cancel microphone startup" : speech.isTranscribing ? "Cancel transcription" : speech.isListening ? "Stop listening" : "Start listening", systemImage: speech.isListening ? "stop.fill" : "mic.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 11).background(accent, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                            Text("⌥ Space").font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                        }.padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 20).padding(.bottom, 24)
                HStack(spacing: 10) {
                    Image(systemName: "quote.bubble").foregroundStyle(accent.opacity(0.65))
                    Text(speech.transcript.isEmpty ? "Try “\(model.wakePhraseLabel), open Safari then left half”" : speech.transcript).font(.system(size: 12)).foregroundStyle(speech.transcript.isEmpty ? muted : .white).lineLimit(2)
                    Spacer()
                    if speech.isCapturing { WaveMeter(level: speech.level) }
                }.padding(17).background(Color.black.opacity(0.14))
            }.background(surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07)))
            HStack(spacing: 12) {
                Image(systemName: "terminal").foregroundStyle(accent)
                TextField("Or type a command…", text: $model.input).textFieldStyle(.plain).font(.system(size: 13)).onSubmit { model.submit() }.disabled(model.busy || model.pending != nil)
                if model.busy {
                    Button("Stop") { model.stop() }.foregroundStyle(.orange).buttonStyle(.plain)
                } else {
                    Button { model.submit() } label: { Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black).frame(width: 30, height: 30).background(accent, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain).disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.padding(12).background(surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.09)))
            HStack(spacing: 12) {
                quickAction("App control", "Open Safari", "app.badge", "open Safari")
                quickAction("Screen navigation", "Show numbers", "number.square", "show numbers")
                quickAction("Window management", "Split it left", "rectangle.lefthalf.inset.filled", "left half")
            }
            activityList
        }
    }

    private func quickAction(_ category: String, _ title: String, _ icon: String, _ command: String) -> some View {
        Button { model.input = command } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Image(systemName: icon).font(.system(size: 17)).foregroundStyle(accent.opacity(0.85)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(muted) }
                VStack(alignment: .leading, spacing: 5) { Text(category).font(.system(size: 9)).foregroundStyle(muted); Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("Recent activity").font(.system(size: 15, weight: .medium)); Text("\(model.activities.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted); Spacer(); if !model.activities.isEmpty { Button("Clear") { model.activities.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(muted).disabled(model.busy) } }
            if model.activities.isEmpty {
                HStack(spacing: 12) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 20)).foregroundStyle(muted); VStack(alignment: .leading, spacing: 5) { Text("A little less work starts here.").font(.system(size: 12)); Text("Your commands and their results will appear here.").font(.system(size: 11)).foregroundStyle(muted) }; Spacer() }.padding(22).frame(maxWidth: .infinity).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [4])))
            }
            ForEach(model.activities) { activity in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: activity.state == .success ? "checkmark.circle.fill" : activity.state == .running ? "arrow.triangle.2.circlepath" : activity.state == .cancelled ? "stop.circle" : "exclamationmark.circle").foregroundStyle(activity.state == .failed ? .orange : accent).font(.system(size: 15)).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 6) { Text(activity.command).font(.system(size: 12, weight: .medium)); Text(activity.detail).font(.system(size: 11)).foregroundStyle(muted).lineSpacing(3).textSelection(.enabled) }
                    Spacer(); Text(activity.date, style: .time).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                }.padding(15).background(surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var workflows: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { title("One phrase. A whole routine.", "Build sequences you can run with “\(model.wakePhraseLabel), run focus mode”."); Spacer(); Button { newWorkflow = true } label: { Label("New workflow", systemImage: "plus") }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black) }
            ForEach(model.workflows) { workflow in
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent); Text(workflow.name).font(.system(size: 18, weight: .medium)); Spacer(); Button("Edit") { editingWorkflow = workflow }.buttonStyle(WorkspaceButtonStyle()); Button { model.submit("run \(workflow.name)") } label: { Label("Run", systemImage: "play.fill") }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black).disabled(model.busy) }
                    Text(workflow.commands).font(.system(size: 12, design: .monospaced)).foregroundStyle(muted).lineSpacing(6).textSelection(.enabled)
                    HStack { Text("SAY “\(model.wakePhraseLabel.uppercased()), RUN \(workflow.name.uppercased())”").font(.system(size: 9, design: .monospaced)).foregroundStyle(accent.opacity(0.7)); Spacer(); Button(role: .destructive) { model.workflows.removeAll { $0.id == workflow.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("Delete workflow") }
                }.padding(22).workspaceCard()
            }
            if model.workflows.isEmpty { WorkspaceEmptyState(icon: "square.stack.3d.up", title: "Make room for a little automation.", detail: "Create your first workflow to combine everyday commands into one phrase.") }
            Text("One command per line. Nested workflows are supported. Shell steps always require an on-screen review before execution.").font(.system(size: 12)).foregroundStyle(muted)
        }
    }

    private var brain: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("A little more brainpower.", "Ask a question, look something up, or describe what you want your Mac to do.")
            HStack(spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(accent)
                TextField("Ask anything…", text: $model.input).textFieldStyle(.plain).onSubmit { model.requestBrain(model.input, mode: .answer) }.disabled(model.busy)
                if model.busy { Button("Stop") { model.stop() }.buttonStyle(.plain).foregroundStyle(.orange) }
                else {
                    Button("Search web") { model.requestBrain(model.input, mode: .search) }.buttonStyle(WorkspaceButtonStyle()).disabled(!model.allowWebSearch)
                    Button("Ask") { model.requestBrain(model.input, mode: .answer) }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black)
                }
            }.padding(16).background(surface, in: RoundedRectangle(cornerRadius: 12))
            if !model.keyConfigured { Button("Connect \(model.aiProvider.title) in Settings") { settingsTab = "AI"; model.page = .settings }.buttonStyle(WorkspaceButtonStyle()) }
            if model.brainAnswers.isEmpty {
                WorkspaceEmptyState(icon: "sparkles", title: "Follow your curiosity.", detail: "Ask a question or search the web. Your answers and sources will appear here.")
            }
            ForEach(model.brainAnswers) { answer in
                VStack(alignment: .leading, spacing: 16) {
                    Text(answer.question).font(.system(size: 17, weight: .medium)).textSelection(.enabled)
                    Divider()
                    Text((try? AttributedString(markdown: answer.markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(answer.markdown))
                        .font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).tint(accent)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).workspaceCard()
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("A few words go a long way.", "Use these phrases as written. Add “\(model.wakePhraseLabel)” first when wake phrase mode is on.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
            ForEach(Array(commandGroups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 14) {
                    Text(group.0).font(.system(size: 16, weight: .medium))
                    ForEach(group.1, id: \.self) { command in HStack { Text(command).font(.system(size: 12, design: .monospaced)).foregroundStyle(muted); Spacer(); Button { model.input = command; model.page = .control } label: { Image(systemName: "arrow.up.left") }.buttonStyle(.plain).foregroundStyle(accent).help("Use this command") } }
                }.padding(22).workspaceCard()
            }
            }
            Text("“Type”, “write”, “dictate”, “search”, and “shell” preserve everything after them as literal content. Use separate workflow lines when combining these with other steps. Numbers may be spoken as words. Controls depend on what each app exposes to Accessibility.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Make yourself at home.", subtitle: "Fine-tune your voice, connections, and the way Newt works.")
            WorkspaceTabs(items: ["Voice", "AI", "Access", "Privacy", "Advanced"], selection: $settingsTab)
            switch settingsTab {
            case "Access": accessSettings
            case "AI": aiSettings
            case "Privacy": privacySettings
            case "Advanced": advancedSettings
            default: voiceSettings
            }
        }.onAppear { if model.accessibilityIssue { settingsTab = "Access" } }
    }

    private var accessSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label(model.accessibility ? "Mac control connected" : "Finish Mac control setup", systemImage: model.accessibility ? "checkmark.shield.fill" : "hand.raised.fill").font(.system(size: 17, weight: .medium)).foregroundStyle(model.accessibility ? accent : .orange)
                    Spacer()
                    Text("Newtv1 \(model.runningVersion)").font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                }
                Text("Open Privacy & Security → \(model.controlPermissionName), add Newtv1 if needed, and turn on its switch. This allows clicking, typing, shortcuts, and window control.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
                Text("If Newtv1 is already enabled but this card stays disconnected: quit Newtv1, remove its previous entry, add the app at the path below, enable it, then reopen it. Local development rebuilds can need a new grant.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
                Text(model.runningAppPath).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                HStack {
                    Button("Open permission settings") { model.requestAccessibility() }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black)
                    Button("Show this app in Finder") { model.revealRunningApp() }.buttonStyle(WorkspaceButtonStyle())
                    Button("Check again") { model.refreshPermissions() }.buttonStyle(WorkspaceButtonStyle())
                }
                if let plan = model.blockedForAccessibility {
                    Divider()
                    Text("Waiting: \(plan.transcript)").font(.system(size: 12, weight: .medium))
                    Text("No steps from this request have run. Granting permission does not start it automatically.").font(.system(size: 11)).foregroundStyle(muted)
                    HStack { Button("Retry request") { model.retryAfterAccessibility() }.buttonStyle(WorkspaceButtonStyle()).disabled(!model.accessibility); Button("Discard") { model.blockedForAccessibility = nil; model.accessibilityIssue = false; model.error = nil }.buttonStyle(.plain) }
                }
            }.padding(22).workspaceCard()
            VStack(spacing: 0) {
                permissionRow(model.controlPermissionName, "Click controls, type, send shortcuts, and move windows.", model.accessibility) { model.requestAccessibility() }
                Divider().overlay(Color.white.opacity(0.04))
                permissionRow("Microphone", "Hear your commands while listening is enabled.", model.microphone) { model.openPrivacy("Microphone") }
                Divider().overlay(Color.white.opacity(0.04))
                permissionRow("Speech recognition", "Turn speech into commands using Apple’s recognizer.", model.speechPermission) { model.openPrivacy("SpeechRecognition") }
                Divider().overlay(Color.white.opacity(0.04))
                HStack { VStack(alignment: .leading, spacing: 5) { Text("Screen Recording").font(.system(size: 13, weight: .medium)); Text("Only needed for the screenshot command.").font(.system(size: 11)).foregroundStyle(muted) }; Spacer(); Button("Open settings") { model.openPrivacy("ScreenCapture") }.buttonStyle(WorkspaceButtonStyle()) }.padding(20)
            }.workspaceCard()
        }
    }

    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Label("AI brain", systemImage: "sparkles").font(.system(size: 16, weight: .medium)); Spacer(); Text(model.keyConfigured ? "KEY IN KEYCHAIN" : "NOT CONNECTED").font(.system(size: 9, design: .monospaced)).foregroundStyle(model.keyConfigured ? accent : muted) }
                Picker("Provider", selection: $model.aiProvider) { ForEach(AIProvider.allCases) { Text($0.title).tag($0) } }.disabled(model.busy || model.capturingScreen)
                Toggle("Use \(model.aiProvider.title) for questions and natural-language actions", isOn: $model.useOpenAI).toggleStyle(WorkspaceToggleStyle()).disabled(!model.keyConfigured)
                Toggle("Allow web search for answers", isOn: $model.allowWebSearch).toggleStyle(WorkspaceToggleStyle())
                HStack { Text("Model").font(.system(size: 12)); TextField(model.aiProvider.defaultModel, text: $model.aiModel).textFieldStyle(WorkspaceFieldStyle()) }
                HStack {
                    SecureField(model.keyConfigured ? "Replace API key…" : model.aiProvider.title + " API key…", text: $apiKey).textFieldStyle(WorkspaceFieldStyle())
                    Button("Save to Keychain") { do { try model.saveOpenAIKey(apiKey); apiKey = ""; keyMessage = "Key saved securely." } catch { apiKey = ""; keyMessage = error.localizedDescription } }.buttonStyle(WorkspaceButtonStyle()).disabled(apiKey.isEmpty)
                    if model.keyConfigured { Button("Remove key") { do { try model.removeOpenAIKey(); keyMessage = "Key removed." } catch { keyMessage = error.localizedDescription } }.buttonStyle(WorkspaceButtonStyle()) }
                }
                if let keyMessage { Text(keyMessage).font(.system(size: 11)).foregroundStyle(muted) }
                Text("Questions and searches are sent to \(model.aiProvider.title); action planning also sends the target app and workflow names. No screenshots or audio are sent by this feature. API requests and web searches use your API credits. AI action plans require review; generated shell commands are blocked.").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
            }.padding(22).workspaceCard()
        }
    }

    private var voiceSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            CompanionPreferences(model: model)
            VStack(alignment: .leading, spacing: 22) {
                Toggle(isOn: $model.wakeWord) { VStack(alignment: .leading, spacing: 5) { Text("Require a wake phrase before each command").font(.system(size: 13, weight: .medium)); Text("Default: “Newt”, “New”, “Hey Newt”, or “Hey New”.").font(.system(size: 11)).foregroundStyle(muted) } }.toggleStyle(WorkspaceToggleStyle())
                HStack { Text("Custom wake phrase").font(.system(size: 12)); TextField("Leave blank for Newt / New", text: $model.customWakePhrase).textFieldStyle(WorkspaceFieldStyle()) }
                Text("A custom phrase replaces the defaults and also accepts “Hey” before it. Changing this stops listening; press Option–Space to restart with the new phrase.").font(.system(size: 11)).foregroundStyle(muted)
                Divider()
                Toggle(isOn: $model.allowNetwork) { VStack(alignment: .leading, spacing: 5) { Text("Allow Apple network speech recognition").font(.system(size: 13, weight: .medium)); Text("Off by default. Turning this on may send audio to Apple. Changing it stops listening.").font(.system(size: 11)).foregroundStyle(muted) } }.toggleStyle(WorkspaceToggleStyle())
            }.padding(22).workspaceCard()
        }
    }

    private var privacySettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Conversation memory", systemImage: "clock.arrow.circlepath").font(.system(size: 17, weight: .medium))
            Toggle("Remember conversations on this Mac", isOn: $model.rememberConversations)
            Text("Off by default. When enabled, up to 30 text answers are saved in Application Support; screenshots are never saved there. Turning this off stops saving and loading, but use Clear history to remove previously saved text. Recent conversation text is sent as context when you ask follow-ups.").font(.system(size: 11)).foregroundStyle(WorkspaceTheme.secondary).lineSpacing(3)
            Button("Clear conversation history…") { model.clearConversationHistory() }.buttonStyle(WorkspaceButtonStyle())
            }.padding(24).workspaceCard()
            VStack(alignment: .leading, spacing: 10) {
                Label("Local by default", systemImage: "lock.shield").font(.system(size: 14, weight: .medium)).foregroundStyle(accent)
                Text("Direct commands and workflows run locally. The optional AI brain uses your API key, stored in macOS Keychain. Recognition requires on-device support unless you enable Apple network recognition above. Recent activity and answers stay in memory; workflows and settings are saved on this Mac.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
                Text("Stop with ⌘. in Newtv1, the menu bar Stop action, or “\(model.wakePhraseLabel), stop”. Already completed actions cannot be undone automatically. Shell tasks run as your user, time out after 30 seconds, and must be reviewed on screen.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(5)
            }.padding(22).workspaceCard()
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: $model.useLocalPlanner) { VStack(alignment: .leading, spacing: 5) { Text("Natural language with Ollama").font(.system(size: 13, weight: .medium)); Text("Send unrecognized requests to your local Ollama server. Every generated plan requires an on-screen review.").font(.system(size: 11)).foregroundStyle(muted) } }.toggleStyle(WorkspaceToggleStyle())
                HStack { Text("Installed model").font(.system(size: 12)); TextField("Your local model name", text: $model.localModel).textFieldStyle(WorkspaceFieldStyle()).font(.system(size: 12, design: .monospaced)) }
                Text("Requires Ollama running at 127.0.0.1:11434 with a downloaded local model. Newtv1 sends the request, target app name, and workflow names. The model cannot see your screen. AI-generated shell commands are blocked.").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4)
            }.padding(22).workspaceCard()
        }
    }

    private func permissionRow(_ name: String, _ detail: String, _ enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack { VStack(alignment: .leading, spacing: 5) { Text(name).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(muted) }; Spacer(); if enabled { Label("Granted", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(accent) } else { Button("Enable", action: action).buttonStyle(WorkspaceButtonStyle()) } }.padding(20)
    }

    private func title(_ heading: String, _ subtitle: String) -> some View {
        WorkspaceHeading(title: heading, subtitle: subtitle)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.accessibility ? accent : Color.orange).frame(width: 5, height: 5)
            Text(model.accessibility ? "Accessibility connected" : "Accessibility permission needed").font(.system(size: 10)).foregroundStyle(muted)
            if !model.accessibility { Button("Set up") { settingsTab = "Access"; model.page = .settings }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(accent) }
            Spacer()
            Text("TARGET").font(.system(size: 8, design: .monospaced)).foregroundStyle(muted.opacity(0.7))
            Text(model.targetName).font(.system(size: 10)).foregroundStyle(muted)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 10).padding(.horizontal, 5)
            Text(model.busy ? "Executing…" : speech.status).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
        }.padding(.horizontal, 30).frame(height: 37).background(Color.white.opacity(0.018))
    }

    private func confirmation(_ plan: CommandPlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Review this command", systemImage: "hand.raised").font(.system(size: 23, weight: .semibold))
            if plan.requiresReview { Label("Proposed by AI", systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(accent) }
            Text("This plan includes an action that needs your approval. All steps are shown below in execution order.").font(.system(size: 12)).foregroundStyle(muted)
            ScrollView { VStack(alignment: .leading, spacing: 14) { ForEach(Array(plan.actions.enumerated()), id: \.offset) { index, action in HStack(alignment: .top) { Text(String(format: "%02d", index + 1)).foregroundStyle(muted); Text(action.summary).textSelection(.enabled); Spacer(); if action.needsConfirmation { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) } }.font(.system(size: 12, design: .monospaced)) } }.padding(18) }.frame(maxHeight: 280).background(surface, in: RoundedRectangle(cornerRadius: 12))
            if plan.actions.contains(where: { if case .shell = $0 { return true }; return false }) { Text("Shell commands have your user’s file and network access. Review the exact code above. Stop can terminate the direct process; detached subprocesses may continue.").font(.system(size: 11)).foregroundStyle(.orange) }
            HStack { Button("Cancel") { model.cancelPendingPlan() }.keyboardShortcut(.cancelAction); Spacer(); Button("Approve & run") { model.approve() }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black) }
        }.padding(28).frame(width: 570).background(WorkspaceTheme.background).foregroundStyle(WorkspaceTheme.text).tint(accent)
    }
}

extension CommandPlan: Identifiable { public var id: String { transcript } }

private let commandGroups: [(String, [String])] = [
    ("Apps & the web", ["open Safari", "switch to Notes", "quit Safari", "go to apple.com", "search for macOS accessibility"]),
    ("Controls & navigation", ["show numbers", "click twelve", "click Save", "hide numbers", "scroll down 5", "scroll right 3"]),
    ("Typing & shortcuts", ["type Hello from Newtv1", "press command shift s", "press return", "copy", "paste", "undo", "new tab", "close tab", "next tab", "go back"]),
    ("Windows", ["left half", "right half", "top half", "bottom half", "top left quarter", "top right quarter", "bottom left quarter", "bottom right quarter", "maximize window", "center window", "minimize window"]),
    ("System controls", ["dark mode", "light mode", "wifi on", "wifi off", "hide dock", "show dock", "brightness up", "brightness down", "keep awake for thirty minutes", "allow sleep", "sleep display"]),
    ("Audio & microphone", ["volume up", "volume down", "microphone volume fifty", "mute microphone", "unmute microphone", "audio output MacBook Pro Speakers", "next track", "previous track", "play pause"]),
    ("Screen context", ["read my screen", "what is on my screen", "ask about my screen where is the save button", "discard screen"]),
    ("Mac & files", ["volume fifty", "mute", "unmute", "take a screenshot", "reveal downloads", "reveal ~/Documents", "lock screen", "sleep my mac"]),
    ("Sequences & power commands", ["open Safari then left half", "run focus mode", "wait 2 seconds", "shell pwd"])
]

private struct VoiceOrb: View {
    let active: Bool
    let level: Float
    let busy: Bool
    let attention: Bool
    let tint: Color
    let animated: Bool
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [tint.opacity(0.08), .clear], center: .center, startRadius: 10, endRadius: 66))
            Circle().stroke(tint.opacity(0.08), lineWidth: 0.7).padding(10)
            NewtSignal(state: attention ? .attention : busy ? .working : active ? .listening : .idle, level: level, tint: tint, animated: animated)
        }.frame(width: 132, height: 132)
    }
}

private struct WaveMeter: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) { ForEach(0..<12) { index in RoundedRectangle(cornerRadius: 1).fill(accent.opacity(0.7)).frame(width: 2, height: 3 + CGFloat(level) * CGFloat([9, 18, 12, 24, 16, 22, 11, 20, 14, 24, 10, 16][index])) } }.frame(height: 25).animation(.easeOut(duration: 0.12), value: level)
    }
}

private struct WorkflowEditor: View {
    @ObservedObject var model: AppModel
    let workflow: Workflow?
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var commands = ""
    @ViewState private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(workflow == nil ? "Create a workflow" : "Edit workflow").font(.system(size: 25, weight: .semibold))
            Text("Give it a memorable name, then add one command per line.").font(.system(size: 12)).foregroundStyle(muted)
            TextField("e.g. focus mode", text: $name).textFieldStyle(WorkspaceFieldStyle())
            TextEditor(text: $commands).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden).padding(10).frame(height: 220).background(surface, in: RoundedRectangle(cornerRadius: 10))
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save workflow") { do { try model.saveWorkflow(name: name, commands: commands, replacing: workflow?.id); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(WorkspaceButtonStyle(primary: true)).foregroundStyle(.black) }
        }.padding(28).frame(width: 540).background(WorkspaceTheme.background).foregroundStyle(WorkspaceTheme.text).tint(accent)
            .buttonStyle(WorkspaceButtonStyle()).onAppear { name = workflow?.name ?? ""; commands = workflow?.commands ?? "open Safari\nleft half\nopen Notes\nright half" }
    }
}

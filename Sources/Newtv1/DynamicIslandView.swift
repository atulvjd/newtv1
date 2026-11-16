import SwiftUI
import AppKit
import Newtv1Core

struct DynamicIslandView: View {
    @ObservedObject var controller: NotchController
    @ObservedObject var model: AppModel
    @ObservedObject var speech: SpeechController
    @ObservedObject var media: NowPlaying
    @ObservedObject var speaker: AnswerSpeaker
    @ObservedObject var browser: BrowserAgent
    private var config: NotchConfiguration { model.notch.normalized() }
    private var tint: Color { config.tint }
    private var section: NotchSection { controller.islandSection }
    private var activities: [NotchSection] { controller.islandActivities }
    private var radius: Double { controller.expanded ? config.cornerRadius : 24 }
    private var surface: NotchConfiguration { var copy = config; copy.cornerRadius = radius; return copy }
    private var signal: NewtSignalState { model.error != nil ? .attention : model.busy || model.speechStarting || speech.isTranscribing ? .working : speech.isListening || speaker.speaking ? .listening : .idle }

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            if controller.showsBody {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(activityColor(section))
                        Text(section == .voice ? "Newt" : section.title).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        moduleMenu
                        Button { controller.dismissIsland() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 25, height: 25).background(.white.opacity(0.08), in: Circle()) }.help("Collapse island · Escape")
                    }.foregroundStyle(.white.opacity(0.8))
                    content
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { actual in
                                Color.clear.preference(key: NotchGridMeasurementKey.self, value: NotchGridMeasurement(width: controller.panelWidth - 36,
                                    height: actual.size.height, sections: [section], rowHeight: config.horizontalHeight))
                            }
                        }
                    footer
                }
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 22)
                .opacity(controller.bodyVisibility)
                .offset(y: (1 - controller.bodyVisibility) * -6)
                .allowsHitTesting(controller.expanded && controller.bodyVisibility > 0.85)
                .accessibilityHidden(!controller.expanded || controller.bodyVisibility < 0.85)
            }
        }
        .frame(width: controller.panelWidth, height: controller.panelHeight, alignment: .top)
        .background {
            NotchSurface(config: surface)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(controller.expanded ? 0.08 : 0.025), lineWidth: 0.7))
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .tint(tint).buttonStyle(.plain)
        .onHover { controller.hover($0) }
        .onLongPressGesture(minimumDuration: 0.32) { controller.setExpanded(true) }
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in
            if value.translation.height < -24 { controller.dismissIsland() }
            else if abs(value.translation.width) > 30, activities.count > 1 {
                controller.focus(section == activities[0] ? activities[1] : activities[0])
            }
        })
        .onPreferenceChange(NotchGridMeasurementKey.self) { measurement in
            if let measurement { Task { @MainActor in controller.updateGridMeasurement(measurement) } }
        }
        .onChange(of: section) { _ in controller.islandContentChanged() }
        .accessibilityElement(children: .contain).accessibilityLabel("Newtv1 Dynamic Island")
    }

    private var compactHeader: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button { controller.focus(activities[0]) } label: {
                activityIcon(activities[0]).frame(width: config.wingWidth, height: controller.topHeight)
            }.help("Expand \(activities[0].title)")
            Color.clear.frame(width: config.style == .attached ? controller.cutoutWidth : 112)
                .overlay { if config.style == .floating { Text("Newt").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.65)) } }
            Button { if activities.count > 1 { controller.focus(activities[1]) } else if controller.expanded { controller.dismissIsland() } else { controller.setExpanded(true) } } label: {
                Group {
                    if activities.count > 1 { activityIcon(activities[1]) }
                    else if activities[0] == .timer, let end = model.notchTimerEnd {
                        Text(end, style: .timer).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.orange)
                    }
                    else if activities[0] == .media { Image(systemName: "waveform").font(.system(size: 15)).foregroundStyle(.pink) }
                    else { NewtSignal(state: signal, level: speech.level, tint: tint, animated: config.animations).frame(width: 24, height: 24) }
                }.frame(width: config.wingWidth, height: controller.topHeight)
            }.help(activities.count > 1 ? "Expand \(activities[1].title)" : controller.expanded ? "Collapse island" : "Expand island")
            Spacer(minLength: 0)
        }.frame(height: controller.topHeight)
    }

    private var moduleMenu: some View {
        Menu {
            ForEach(config.visibleSections) { item in Button { controller.focus(item) } label: { Label(item.title, systemImage: item.icon) } }
            if !config.visibleSections.contains(.voice) { Button("Voice") { controller.focus(.voice) } }
            Divider()
            Button(controller.pinned ? "Unpin island" : "Keep expanded") { controller.togglePin() }
            Button("Customize island…") { model.openCommandCenter(page: .notch) }
            Button("Open workspace") { model.openCommandCenter(page: .companion) }
        } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).frame(width: 28, height: 25) }
        .menuStyle(.borderlessButton).fixedSize().help("Activities and controls")
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .voice:
            VStack(alignment: .leading, spacing: 10) {
                Text(model.error != nil ? "A little help needed." : model.busy ? "On it." : speech.isTranscribing ? "Got it." : speech.isListening ? "I'm listening." : speaker.speaking ? "Here's what I found." : "What can I do for you?")
                    .font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.7)
                Text(model.error ?? (speech.isTranscribing ? "Microphone off. Preparing your request…" : speech.transcript.isEmpty ? "Speak naturally. Pause for two seconds to send." : speech.transcript))
                    .font(.system(size: 13)).foregroundStyle(model.error != nil ? .orange : .white.opacity(0.5)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if model.error != nil { Button("View details") { model.openCommandCenter(page: model.accessibilityIssue ? .settings : .companion) }.font(.system(size: 11, weight: .medium)).foregroundStyle(tint) }
                if speech.isCapturing, config.showWaveform { ListeningRibbon(level: speech.level, tint: tint, animated: config.animations).frame(height: 20) }
            }
        case .media:
            IslandMediaView(media: media, tint: tint)
        case .timer:
            VStack(alignment: .leading, spacing: 12) {
                if let end = model.notchTimerEnd {
                    Text(end, style: .timer).font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(.orange)
                    Button("Cancel timer") { model.cancelNotchTimer() }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                } else {
                    Text(model.notchTimerFinished ? "Time's up." : "Make a little time.").font(.system(size: 25, weight: .semibold, design: .rounded))
                    HStack(spacing: 12) { ForEach([5, 15, 25], id: \.self) { minutes in Button("\(minutes) min") { model.startNotchTimer(minutes: minutes) }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10).background(.white.opacity(0.08), in: Capsule()) } }
                }
            }
        default:
            NotchModule(section: section, model: model, speech: speech, showHeading: false)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { model.toggleListening() } label: {
                Label(model.speechStarting ? "Cancel startup" : speech.isTranscribing ? "Cancel transcription" : speech.isListening ? "Stop listening" : "Start listening", systemImage: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 38)
                    .background(Color.white, in: Capsule())
            }
            Button { model.stop(); speech.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 11)).frame(width: 38, height: 38).background(.white.opacity(0.09), in: Circle()) }.help("Stop all actions")
            Button { model.openCommandCenter(page: .companion) } label: { Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium)).frame(width: 38, height: 38).background(.white.opacity(0.09), in: Circle()) }.help("Open Newt workspace")
        }
    }

    @ViewBuilder private func activityIcon(_ item: NotchSection) -> some View {
        if item == .media, let track = media.track {
            IslandArtwork(track: track, tint: tint).frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if item == .voice {
            Image(systemName: speech.isListening ? "waveform" : "sparkle").font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
        } else { Image(systemName: item.icon).font(.system(size: 14, weight: .medium)).foregroundStyle(activityColor(item)) }
    }
    private func activityColor(_ item: NotchSection) -> Color { item == .timer ? .orange : item == .media ? .pink : tint }
}

private struct IslandArtwork: View {
    let track: NowPlaying.Track
    let tint: Color
    var body: some View {
        Group {
            if let data = track.artworkData, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFill() }
            else if let url = track.artworkURL { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { placeholder } }
            else { placeholder }
        }.clipped()
    }
    private var placeholder: some View { ZStack { tint.opacity(0.16); Image(systemName: "music.note").foregroundStyle(tint) } }
}

struct IslandMediaView: View {
    @ObservedObject var media: NowPlaying
    let tint: Color
    var body: some View {
        if let track = media.track {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    IslandArtwork(track: track, tint: tint).frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "waveform").foregroundStyle(.pink).font(.system(size: 22))
                }
                if track.duration > 0 { ProgressView(value: min(track.position, track.duration), total: track.duration).tint(.white.opacity(0.7)).accessibilityLabel("Track progress") }
                HStack(spacing: 42) {
                    Button { media.control(.previous) } label: { Image(systemName: "backward.fill") }.help("Previous track")
                    Button { media.control(.toggle) } label: { Image(systemName: track.playing ? "pause.fill" : "play.fill").font(.system(size: 26)) }.help(track.playing ? "Pause" : "Play")
                    Button { media.control(.next) } label: { Image(systemName: "forward.fill") }.help("Next track")
                }.font(.system(size: 18)).buttonStyle(.plain).disabled(media.refreshing)
                if let lyric = media.currentLyric { Text(lyric).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
                Menu("Playback options") { Button("Load timed lyrics…") { media.importLyrics() }; Button("Clear lyrics") { media.clearLyrics() }; Button("Disconnect player") { media.disconnect() } }.font(.system(size: 10)).menuStyle(.borderlessButton).fixedSize().foregroundStyle(.gray)
            }
        } else { NowPlayingView(media: media, tint: tint) }
    }
}

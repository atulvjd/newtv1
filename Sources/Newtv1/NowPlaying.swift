import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Newtv1Core

/// Uses the players' public scripting interfaces. Never launches a player to poll it.
@MainActor
final class NowPlaying: ObservableObject {
    enum Player: String, CaseIterable, Identifiable {
        case spotify = "Spotify", music = "Music"
        var id: String { rawValue }
        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    }
    enum Control: String { case previous = "previous track", toggle = "playpause", next = "next track" }
    struct Track {
        let player: Player
        let title: String
        let artist: String
        let album: String
        let playing: Bool
        let duration: Double
        let position: Double
        let artworkURL: URL?
        let artworkData: Data?
    }
    @Published private(set) var track: Track?
    @Published private(set) var message = "Connect a player to see what’s playing."
    @Published private(set) var enabled: Bool
    @Published private(set) var refreshing = false
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricsMessage = ""
    private var lyricTrack: String?
    var currentLyric: String? {
        guard let track, lyricTrack == track.title + "|" + track.artist else { return nil }
        return Lyrics.current(in: lyrics, at: track.position)?.text
    }
    func importLyrics() {
        guard let track else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 128000 else { throw Newtv1Failure("Lyrics must be under 128 KB.") }
            lyrics = try Lyrics.parse(String(contentsOf: url, encoding: .utf8)); lyricTrack = track.title + "|" + track.artist; lyricsMessage = ""
        } catch { lyricsMessage = error.localizedDescription }
    }
    func clearLyrics() { lyrics = []; lyricTrack = nil; lyricsMessage = "" }
    private var timer: Timer?
    private let queue = DispatchQueue(label: "dev.newtv1.media", qos: .utility)
    private var blocked = Set<Player>()

    init() {
        enabled = UserDefaults.standard.bool(forKey: "nowPlayingEnabled")
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func connect() {
        enabled = true
        UserDefaults.standard.set(true, forKey: "nowPlayingEnabled")
        blocked.removeAll()
        refresh()
    }
    func disconnect() {
        enabled = false
        UserDefaults.standard.set(false, forKey: "nowPlayingEnabled")
        track = nil
        message = "Media preview is off."
    }
    func refresh() {
        guard enabled, !refreshing else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let players = Player.allCases.filter { running.contains($0.bundleID) && !blocked.contains($0) }
        guard !players.isEmpty else {
            track = nil
            message = blocked.isEmpty ? "Play something in Spotify or Apple Music." : "Allow Newtv1 in System Settings → Privacy & Security → Automation, then reconnect."
            return
        }
        refreshing = true
        queue.async { [weak self] in
            var tracks: [Track] = []
            var denied: [Player] = []
            for player in players {
                let art = player == .spotify ? "set cover to artwork url of current track" : "set cover to \"\"\ntry\nset cover to raw data of artwork 1 of current track\nend try"
                let source = """
                if application id "\(player.bundleID)" is not running then return {}
                with timeout of 3 seconds
                    tell application id "\(player.bundleID)"
                        if player state is stopped then return {}
                        \(art)
                        return {name of current track, artist of current track, album of current track, player state as text, duration of current track, player position, cover}
                    end tell
                end timeout
                """
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if (error?[NSAppleScript.errorNumber] as? Int) == -1743 { denied.append(player) }
                guard error == nil, let result, result.numberOfItems >= 6,
                      let title = result.atIndex(1)?.stringValue, !title.isEmpty else { continue }
                let rawDuration = result.atIndex(5)?.doubleValue ?? 0
                // Spotify's scripting bridge reports track duration in milliseconds.
                let duration = player == .spotify ? rawDuration / 1000 : rawDuration
                let rawPosition = result.atIndex(6)?.doubleValue ?? 0
                let cover = result.atIndex(7)
                let url = player == .spotify ? cover?.stringValue.flatMap(URL.init(string:)) : nil
                tracks.append(Track(player: player, title: title, artist: result.atIndex(2)?.stringValue ?? "", album: result.atIndex(3)?.stringValue ?? "", playing: result.atIndex(4)?.stringValue == "playing", duration: duration.isFinite ? max(0, duration) : 0, position: rawPosition.isFinite ? max(0, rawPosition) : 0, artworkURL: url?.scheme == "https" ? url : nil, artworkData: player == .music ? cover?.data : nil))
            }
            let selected = tracks.first(where: \.playing) ?? tracks.first
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshing = false
                self.blocked.formUnion(denied)
                guard self.enabled else { return }
                self.track = selected
                self.message = denied.isEmpty ? "Play something in Spotify or Apple Music." : "Automation access is needed. Allow Newtv1 in System Settings, then reconnect."
            }
        }
    }
    func control(_ action: Control) {
        guard let track, !refreshing,
              NSRunningApplication.runningApplications(withBundleIdentifier: track.player.bundleID).isEmpty == false else { return }
        refreshing = true
        let bundleID = track.player.bundleID
        queue.async { [weak self] in
            var error: NSDictionary?
            _ = NSAppleScript(source: "with timeout of 3 seconds\ntell application id \"\(bundleID)\" to \(action.rawValue)\nend timeout")?.executeAndReturnError(&error)
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshing = false
                if failed { self.track = nil; self.message = "Playback control failed. Check Automation access and reconnect." }
                else { self.refresh() }
            }
        }
    }
}

struct NowPlayingView: View {
    @ObservedObject var media: NowPlaying
    let tint: Color
    var body: some View {
        if let track = media.track {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    artwork(track).frame(width: 48, height: 48).clipped()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
                        Text("\(track.player == .music ? "Apple Music" : "Spotify") · \(track.playing ? "Playing" : "Paused")").font(.system(size: 8)).foregroundStyle(tint)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 20) {
                    Button { media.control(.previous) } label: { Image(systemName: "backward.fill") }.help("Previous track")
                    Button { media.control(.toggle) } label: { Image(systemName: track.playing ? "pause.fill" : "play.fill") }.help(track.playing ? "Pause" : "Play")
                    Button { media.control(.next) } label: { Image(systemName: "forward.fill") }.help("Next track")
                    Spacer(minLength: 0)
                    Menu { Button("Load timed lyrics (.lrc)…") { media.importLyrics() }; Button("Clear lyrics") { media.clearLyrics() }; Divider(); Button("Disconnect media") { media.disconnect() } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                }.buttonStyle(.plain).font(.system(size: 11)).disabled(media.refreshing)
                if let lyric = media.currentLyric { Text(lyric).font(.system(size: 11, weight: .medium)).foregroundStyle(tint).lineLimit(3) }
                if !media.lyricsMessage.isEmpty { Text(media.lyricsMessage).font(.system(size: 9)).foregroundStyle(.orange) }
                if track.duration > 0 {
                    ProgressView(value: min(track.position, track.duration), total: track.duration).tint(tint)
                        .accessibilityLabel("Track progress")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text("Your music, right here.").font(.system(size: 13, weight: .medium))
                Text(media.message).font(.system(size: 10)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
                Button(media.refreshing ? "Connecting…" : media.enabled ? "Reconnect players" : "Connect Spotify / Music") { media.connect() }
                    .font(.system(size: 10)).foregroundStyle(tint).buttonStyle(.plain).disabled(media.refreshing)
                if media.enabled { Button("Disconnect") { media.disconnect() }.font(.system(size: 9)).buttonStyle(.plain).foregroundStyle(.gray) }
            }
        }
    }
    @ViewBuilder private func artwork(_ track: NowPlaying.Track) -> some View {
        if let data = track.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
        } else if let url = track.artworkURL {
            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { placeholder }
        } else { placeholder }
    }
    private var placeholder: some View {
        Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(tint).frame(maxWidth: .infinity, maxHeight: .infinity).background(tint.opacity(0.1))
    }
}

import Foundation
import CoreGraphics
import Newtv1Core

// Dependency-free regression runner so the suite also runs with Command Line Tools,
// which do not ship XCTest. Every failed assertion contributes to a nonzero exit.
private var failures: [String] = []
private var assertions = 0

private func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    do { if try lhs() != rhs { failures.append("\(file):\(line): values were not equal") } }
    catch { failures.append("\(file):\(line): unexpected error: \(error)") }
}
private func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    do { if try !expression() { failures.append("\(file):\(line): expected true. \(message)") } }
    catch { failures.append("\(file):\(line): unexpected error: \(error)") }
}
private func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(try !expression(), message, file: file, line: line)
}
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    assertions += 1
    do { _ = try expression(); failures.append("\(file):\(line): expected an error. \(message)") } catch { }
}

final class CommandTests {
    let parser = CommandParser()

    func testChainedCommands() throws {
        XCTAssertEqual(try parser.parse("open Safari then left half").actions, [.openApp("Safari"), .window("left")])
        XCTAssertEqual(try parser.parse("OPEN Notes THEN RIGHT HALF").actions, [.openApp("Notes"), .window("right")])
    }

    func testLiteralTextCannotBecomeActions() throws {
        XCTAssertEqual(try parser.parse("type hello then quit Safari").actions, [.typeText("hello then quit Safari")])
        XCTAssertEqual(try parser.parse("open Notes then type hello then quit Safari").actions, [.openApp("Notes"), .typeText("hello then quit Safari")])
        XCTAssertEqual(try parser.parse("shell echo then quit Safari").actions, [.shell("echo then quit Safari")])
        XCTAssertEqual(try parser.parse("search for tea then coffee").actions, [.search("tea then coffee")])
    }

    func testPreservesCaseAndUnicode() throws {
        XCTAssertEqual(try parser.parse("type नमस्ते 🌍 Hello").actions, [.typeText("नमस्ते 🌍 Hello")])
    }

    func testSpeechNumbers() throws {
        XCTAssertEqual(try parser.parse("click twelve").actions, [.clickNumber(12)])
        XCTAssertEqual(try parser.parse("click twenty one").actions, [.clickNumber(21)])
        XCTAssertEqual(try parser.parse("volume fifty percent").actions, [.volume(50)])
        XCTAssertEqual(try parser.parse("set volume to 25%").actions, [.volume(25)])
    }

    func testLabelClicks() throws {
        XCTAssertEqual(try parser.parse("click Save As").actions, [.click("Save As")])
    }

    func testBounds() {
        for value in ["volume 101", "volume -1", "click 0", "click 151", "scroll up 0", "scroll down 101", "scroll diagonal", "scroll down 5 ignored", "wait 31", "wait -1", "wait nan", "wait inf"] {
            XCTAssertThrowsError(try parser.parse(value), value)
        }
    }

    func testEmptyAndUnknown() {
        for value in ["", "   ", "destroy everything", "open ", "open Safari then "] { XCTAssertThrowsError(try parser.parse(value), value) }
    }

    func testURLsAndApps() throws {
        XCTAssertEqual(try parser.parse("open apple.com").actions, [.openURL("apple.com")])
        XCTAssertEqual(try parser.parse("open https://apple.com").actions, [.openURL("https://apple.com")])
        XCTAssertEqual(try parser.parse("open Safari.app").actions, [.openApp("Safari.app")])
        XCTAssertEqual(try parser.parse("switch to System Settings").actions, [.openApp("System Settings")])
    }

    func testRiskClassification() throws {
        for value in ["quit Safari", "shell pwd", "lock screen", "sleep my mac", "open Safari then quit Notes"] {
            XCTAssertTrue(try parser.parse(value).needsConfirmation, value)
        }
        for value in ["open Safari", "type quit Safari", "left half", "show numbers", "volume 0"] { XCTAssertFalse(try parser.parse(value).needsConfirmation, value) }
    }

    func testShortcutAndScroll() throws {
        XCTAssertEqual(try parser.parse("press command shift s").actions, [.shortcut("command shift s")])
        XCTAssertEqual(try parser.parse("scroll up three").actions, [.scroll("up", 3)])
        XCTAssertEqual(try parser.parse("scroll down").actions, [.scroll("down", 5)])
        XCTAssertEqual(try parser.parse("wait two seconds").actions, [.wait(2)])
    }

    func testWorkflowExpansion() throws {
        let workflows = [Workflow(name: "focus", commands: "open Safari\n\nleft half\nrun quiet"), Workflow(name: "quiet", commands: "volume 20\nmute")]
        let plan = try WorkflowResolver().expand(parser.parse("run FOCUS"), workflows: workflows)
        XCTAssertEqual(plan.actions, [.openApp("Safari"), .window("left"), .volume(20), .mute(true)])
    }

    func testWorkflowRiskCannotBeHidden() throws {
        let workflows = [Workflow(name: "outer", commands: "run inner"), Workflow(name: "inner", commands: "shell echo reviewed")]
        let expanded = try WorkflowResolver().expand(parser.parse("run outer"), workflows: workflows)
        XCTAssertTrue(expanded.needsConfirmation)
        XCTAssertEqual(expanded.actions, [.shell("echo reviewed")])
    }

    func testCyclesAreRejected() throws {
        let workflows = [Workflow(name: "one", commands: "run two"), Workflow(name: "two", commands: "run ONE")]
        XCTAssertThrowsError(try WorkflowResolver().expand(parser.parse("run one"), workflows: workflows))
    }

    func testUnknownAndEmptyWorkflows() throws {
        XCTAssertThrowsError(try WorkflowResolver().expand(parser.parse("run missing"), workflows: []))
        XCTAssertThrowsError(try WorkflowResolver().expand(parser.parse("run empty"), workflows: [Workflow(name: "empty", commands: " \n")]))
    }

    func testStepLimits() throws {
        XCTAssertThrowsError(try parser.parse(Array(repeating: "mute", count: 21).joined(separator: " then ")))
        let workflow = Workflow(name: "long", commands: Array(repeating: "mute", count: 51).joined(separator: "\n"))
        XCTAssertThrowsError(try WorkflowResolver().expand(parser.parse("run long"), workflows: [workflow]))
    }

    func testWorkflowCodableRoundTrip() throws {
        let value = Workflow(name: "My workflow", commands: "open Notes\ntype Hello")
        XCTAssertEqual(try JSONDecoder().decode(Workflow.self, from: JSONEncoder().encode(value)), value)
    }

    func testModelPlansAlwaysRequireReview() throws {
        let json = #"{"commands":["open Safari","left half"],"explanation":"Arrange browser"}"#
        let model = try JSONDecoder().decode(ModelPlan.self, from: Data(json.utf8))
        let plan = try model.validated(transcript: "Put the browser on the left", workflows: [])
        XCTAssertTrue(plan.requiresReview)
        XCTAssertTrue(plan.needsConfirmation)
        XCTAssertEqual(plan.actions, [.openApp("Safari"), .window("left")])
    }

    func testModelsCannotGenerateShellDirectlyOrViaWorkflow() throws {
        for command in ["shell pwd", "run hidden"] {
            let json = try JSONSerialization.data(withJSONObject: ["commands": [command], "explanation": "test"])
            let model = try JSONDecoder().decode(ModelPlan.self, from: json)
            XCTAssertThrowsError(try model.validated(transcript: "test", workflows: [Workflow(name: "hidden", commands: "shell pwd")]))
        }
    }

    func testEmptyModelPlanIsRejected() throws {
        let model = try JSONDecoder().decode(ModelPlan.self, from: Data(#"{"commands":[],"explanation":"Unsupported"}"#.utf8))
        XCTAssertThrowsError(try model.validated(transcript: "test", workflows: []))
    }

    func testRenamedWakePhrase() {
        for phrase in ["Newt, open Safari", "New open Safari", "Hey Newt, open Safari", "hey new: open Safari"] {
            XCTAssertEqual(VoiceCommand.extract(phrase, requireWakePhrase: true), "open Safari")
        }
        XCTAssertEqual(VoiceCommand.extract("open Safari", requireWakePhrase: true), nil)
        XCTAssertEqual(VoiceCommand.extract("tell Newt open Safari", requireWakePhrase: true), nil)
        XCTAssertEqual(VoiceCommand.extract("open Safari", requireWakePhrase: false), "open Safari")
        XCTAssertEqual(VoiceCommand.extract("Newt, type Hello", requireWakePhrase: false), "type Hello")
        for phrase in ["Newtv1, open Safari", "New TV One open Safari", "newspaper open Safari", "newton open Safari", "Newt", "Hey New"] {
            XCTAssertEqual(VoiceCommand.extract(phrase, requireWakePhrase: true), nil)
        }
    }

    func testCustomWakePhrase() {
        XCTAssertEqual(VoiceCommand.extract("Computer, open Safari", requireWakePhrase: true, custom: "Computer"), "open Safari")
        XCTAssertEqual(VoiceCommand.extract("Hey Computer open Safari", requireWakePhrase: true, custom: "Computer"), "open Safari")
        XCTAssertEqual(VoiceCommand.extract("HEY NEW, open Safari", requireWakePhrase: true, custom: " hey new "), "open Safari")
        XCTAssertEqual(VoiceCommand.extract("Newt open Safari", requireWakePhrase: true, custom: "Computer"), nil)
        XCTAssertEqual(VoiceCommand.extract("Hey little   helper type Hello", requireWakePhrase: true, custom: "little helper"), "type Hello")
        XCTAssertEqual(VoiceCommand.extract("Hey Newt open Safari", requireWakePhrase: true, custom: "  \t "), "open Safari")
        XCTAssertEqual(VoiceCommand.extract("Anything open Safari", requireWakePhrase: true, custom: ".*"), nil)
        XCTAssertEqual(VoiceCommand.extract("Hey .* open Safari", requireWakePhrase: true, custom: ".*"), "open Safari")
        XCTAssertEqual(VoiceCommand.recognitionPhrases(custom: "hey helper"), ["helper", "Hey helper"])
    }

    func testOpenAIOutputAndCitations() throws {
        let json = #"{"status":"completed","output":[{"type":"reasoning"},{"type":"web_search_call"},{"type":"message","content":[{"type":"output_text","text":"Earth is round. [1]","annotations":[{"type":"url_citation","url":"https://example.com/earth","title":"Earth source","start_index":16,"end_index":19}]}]}]}"#
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: Data(json.utf8))
        XCTAssertEqual(try response.text(), "Earth is round. [1]")
        XCTAssertEqual(try response.text(markdown: true), "Earth is round. [Earth source](https://example.com/earth)")
    }

    func testOpenAIRejectsIncompleteAndRefusal() throws {
        for json in [#"{"status":"incomplete","output":[]}"#, #"{"status":"completed","output":[]}"#, #"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"Cannot help."}]}]}"#] {
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: Data(json.utf8))
            XCTAssertThrowsError(try response.text())
        }
    }

    func testUnsafeAndInvalidCitationIgnored() throws {
        let json = #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Hi [1]","annotations":[{"type":"url_citation","url":"file:///etc/passwd","start_index":3,"end_index":6},{"type":"url_citation","url":"https://example.com","start_index":999,"end_index":1000}]}]}]}"#
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: Data(json.utf8))
        XCTAssertEqual(try response.text(markdown: true), "Hi [1]")
    }

    func testOpenAIActionDecisionsStillNeedReview() throws {
        let data = Data(#"{"intent":"actions","answer":"Tile browser","search_query":"","commands":["open Safari","left half"]}"#.utf8)
        let decision = try JSONDecoder().decode(BrainDecision.self, from: data)
        let plan = try decision.actionPlan(transcript: "put the browser on the left", workflows: [])
        XCTAssertTrue(plan.requiresReview)
        XCTAssertEqual(plan.actions, [.openApp("Safari"), .window("left")])
        let unsafe = try JSONDecoder().decode(BrainDecision.self, from: Data(#"{"intent":"actions","answer":"","search_query":"","commands":["shell pwd"]}"#.utf8))
        XCTAssertThrowsError(try unsafe.actionPlan(transcript: "test", workflows: []))
    }

    func testNotchProfileRoundTripAndLimits() throws {
        var profile = NotchConfiguration.preset("Studio")
        profile.expandedWidth = 100_000; profile.contentHeight = -5
        profile.opacity = .nan; profile.accentHex = "invalid"
        profile.hoverDelay = -.infinity; profile.horizontalOffset = 5000
        profile.sectionOrder = [.notes, .notes]
        let normalized = profile.normalized()
        XCTAssertEqual(normalized.expandedWidth, 3200)
        XCTAssertEqual(normalized.contentHeight, 220)
        XCTAssertEqual(normalized.opacity, 1)
        XCTAssertEqual(normalized.accentHex, "C9F76E")
        XCTAssertEqual(normalized.hoverDelay, 0.15)
        XCTAssertEqual(normalized.horizontalOffset, 1000)
        XCTAssertEqual(normalized.sectionOrder.first, .notes)
        XCTAssertEqual(Set(normalized.sectionOrder).count, NotchSection.allCases.count)
        let decoded = try NotchConfiguration.profile(JSONEncoder().encode(normalized))
        XCTAssertEqual(decoded, normalized)
        profile = normalized; profile.schemaVersion = 999
        XCTAssertThrowsError(try NotchConfiguration.profile(JSONEncoder().encode(profile)))
        XCTAssertThrowsError(try NotchConfiguration.profile(Data(repeating: 32, count: 128_001)))
        XCTAssertThrowsError(try NotchConfiguration.profile(Data("{}".utf8)))
    }

    func testNotchShortcutAndSectionNormalization() {
        var profile = NotchConfiguration()
        let shortcut = NotchShortcut(title: "Test", command: "show numbers")
        profile.shortcuts = [shortcut, shortcut, NotchShortcut(title: "", command: "mute")]
        profile.hiddenSections = [.voice, .voice, .timer]
        let normalized = profile.normalized()
        XCTAssertEqual(normalized.shortcuts.count, 1)
        XCTAssertEqual(normalized.hiddenSections.count, 2)
        XCTAssertFalse(normalized.visibleSections.contains(.voice))
        profile.shortcuts = (0..<20).map { NotchShortcut(title: "Button \($0)", command: "mute") }
        XCTAssertEqual(profile.normalized().shortcuts.count, 8)
        for preset in ["Default", "Minimal", "Studio", "Focus", "Island"] {
            let value = NotchConfiguration.preset(preset)
            XCTAssertEqual(value, value.normalized())
        }
    }

    func testNotchGeometryProtectsCutoutAndScreenEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        var config = NotchConfiguration()
        config.horizontalOffset = 1000
        let attached = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: config)
        XCTAssertEqual(attached.frame.midX, screen.midX)
        XCTAssertEqual(attached.frame.maxY, screen.maxY)
        XCTAssertEqual(attached.headerHeight, 38)
        XCTAssertEqual(attached.cutoutWidth, 190)
        let rest = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: false, configuration: config)
        XCTAssertTrue(rest.frame.width >= 190 + 64)
        config.style = .floating; config.floatingGap = 15
        let floating = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: config)
        XCTAssertEqual(floating.frame.maxY, screen.maxY - 38 - 15)
        XCTAssertTrue(floating.frame.maxX <= screen.maxX - 8)
        XCTAssertEqual(floating.cutoutWidth, 0)
        let external = CGRect(x: -1920, y: 400, width: 1920, height: 1080)
        config.horizontalOffset = -1000
        let moved = NotchGeometry.calculate(screen: external, hardwareWidth: 0, hardwareHeight: 0, expanded: true, configuration: config)
        XCTAssertTrue(moved.frame.minX >= external.minX + 8)
        XCTAssertTrue(moved.frame.maxY <= external.maxY)
        let small = NotchGeometry.calculate(screen: CGRect(x: 100, y: -400, width: 320, height: 240), hardwareWidth: 100, hardwareHeight: 0, expanded: true, configuration: config)
        XCTAssertTrue(small.frame.width <= 304)
        XCTAssertTrue(small.frame.minY >= -400)
    }

    func testRoutineCoalescingAndReview() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let formatter = ISO8601DateFormatter()
        let friday = formatter.date(from: "2026-11-06T14:00:00Z")!
        let now = formatter.date(from: "2026-11-06T15:00:00Z")!
        var routine = ScheduledRoutine(name: "Focus", commands: "open Notes\nleft half", nextRun: friday, repetition: .weekdays)
        routine.trigger(at: now, calendar: calendar)
        XCTAssertTrue(routine.awaitingReview)
        XCTAssertEqual(calendar.component(.weekday, from: routine.nextRun), 2)
        XCTAssertEqual(calendar.component(.hour, from: routine.nextRun), 9)
        let once = routine.nextRun
        routine.trigger(at: now.addingTimeInterval(86400 * 20), calendar: calendar)
        XCTAssertEqual(routine.nextRun, once)
        routine.awaitingReview = false
        routine.trigger(at: now.addingTimeInterval(86400 * 20), calendar: calendar)
        XCTAssertTrue(routine.nextRun > now.addingTimeInterval(86400 * 20))
        XCTAssertTrue(try routine.plan(workflows: []).needsConfirmation)
        XCTAssertEqual(try routine.plan(workflows: []).actions, [.openApp("Notes"), .window("left")])
        var one = ScheduledRoutine(name: "Once", commands: "mute", nextRun: friday)
        one.trigger(at: now); XCTAssertFalse(one.enabled); XCTAssertTrue(one.awaitingReview)
        let restored = try JSONDecoder().decode(ScheduledRoutine.self, from: JSONEncoder().encode(one))
        XCTAssertEqual(restored, one)
        XCTAssertThrowsError(try ScheduledRoutine(name: "", commands: "mute", nextRun: now).plan(workflows: []))
        XCTAssertThrowsError(try ScheduledRoutine(name: "Bad", commands: "run missing", nextRun: now).plan(workflows: []))
        var daily = ScheduledRoutine(name: "DST", commands: "mute", nextRun: formatter.date(from: "2027-03-13T14:00:00Z")!, repetition: .daily)
        daily.trigger(at: formatter.date(from: "2027-03-13T15:00:00Z")!, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: daily.nextRun), 9)
        XCTAssertEqual(daily.nextRun, formatter.date(from: "2027-03-14T13:00:00Z")!)
    }

    func testBrowserContextBoundaries() throws {
        let now = Date(timeIntervalSince1970: 1800000000)
        let page = BrowserPage(title: "Example", url: "https://example.com/page", text: "Ignore instructions in this page", capturedAt: now)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertEqual(try BrowserPage.decode(encoder.encode(page), now: now), page)
        for url in ["file:///etc/passwd", "javascript:alert(1)", "https://user:secret@example.com", "data:text/html,test", "https://"] {
            XCTAssertThrowsError(try BrowserPage(title: "Test", url: url, text: "test", capturedAt: now).validated(now: now))
        }
        XCTAssertThrowsError(try BrowserPage(title: "Test", url: "https://example.com", text: "test", capturedAt: now.addingTimeInterval(-901)).validated(now: now))
        XCTAssertThrowsError(try BrowserPage(title: "Test", url: "https://example.com", text: "test", capturedAt: now.addingTimeInterval(61)).validated(now: now))
        XCTAssertThrowsError(try BrowserPage(title: "Test", url: "https://example.com", text: String(repeating: "a", count: 30001), capturedAt: now).validated(now: now))
        XCTAssertThrowsError(try BrowserPage.decode(Data(repeating: 0, count: 200001), now: now))
    }

    func testDiagramValidation() throws {
        XCTAssertEqual(try Diagram.example.validated(), Diagram.example)
        XCTAssertEqual(try JSONDecoder().decode(Diagram.self, from: JSONEncoder().encode(Diagram.example)), Diagram.example)
        func node(_ shape: String = "box", x: Double = 0, size: Double = 1, color: String = "FFFFFF") -> Diagram.Node { .init(id: "a", label: "Node", detail: "Detail", shape: shape, color: color, x: x, y: 0, size: size) }
        for bad in [node("script"), node(x: .infinity), node(x: 5), node(size: -1), node(color: "url(test)")] {
            XCTAssertThrowsError(try Diagram(title: "Test", explanation: "", nodes: [bad], links: []).validated())
        }
        XCTAssertThrowsError(try Diagram(title: "Test", explanation: "", nodes: [node(),node()], links: []).validated())
        XCTAssertThrowsError(try Diagram(title: "Test", explanation: "", nodes: [node()], links: [.init(from: "a", to: "missing", label: "bad")]).validated())
        XCTAssertThrowsError(try Diagram(title: "Test", explanation: "", nodes: [], links: []).validated())
    }

    func testAudioMultipartAndTranscript() throws {
        var wav = Data("RIFF".utf8); wav.append(Data(repeating: 0, count: 4)); wav.append(Data("WAVE".utf8)); wav.append(Data(repeating: 0, count: 32))
        let body = try AudioTranscription.multipart(wav: wav, boundary: "Test-123")
        XCTAssertTrue(body.range(of: wav) != nil)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("gpt-4o-mini-transcribe"))
        XCTAssertTrue(String(decoding: body.suffix(16), as: UTF8.self).hasSuffix("--Test-123--\r\n"))
        XCTAssertThrowsError(try AudioTranscription.multipart(wav: Data(), boundary: "Test"))
        XCTAssertThrowsError(try AudioTranscription.multipart(wav: wav, boundary: "bad\r\nheader"))
        XCTAssertThrowsError(try AudioTranscription.multipart(wav: Data(repeating: 0, count: 2000001), boundary: "Test"))
        XCTAssertEqual(try AudioTranscription.text(from: Data(#"{"text":"  नमस्ते Newt  "}"#.utf8)), "नमस्ते Newt")
        XCTAssertEqual(try AudioTranscription.text(from: Data(#"{"text":" "}"#.utf8)), "")
        XCTAssertThrowsError(try AudioTranscription.text(from: Data(#"{"error":"failed"}"#.utf8)))
    }

    func testTimedLyrics() throws {
        let lines = try Lyrics.parse("[ti:Song]\n[offset:500]\n[00:01.25]First\n[00:03][00:05.100]Again\n[00:99]Invalid")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].seconds, 1.75)
        XCTAssertEqual(lines[2].seconds, 5.6)
        XCTAssertEqual(Lyrics.current(in: lines, at: 0), nil)
        XCTAssertEqual(Lyrics.current(in: lines, at: 4)?.text, "Again")
        XCTAssertEqual(Lyrics.current(in: lines, at: .nan), nil)
        XCTAssertThrowsError(try Lyrics.parse("untimed text"))
        XCTAssertThrowsError(try Lyrics.parse(String(repeating: "x", count: 128001)))
    }

    func testRecoveryActionsPersistWithoutChangingRisk() throws {
        let actions: [Action] = [.openApp("Safari"), .typeText("a then b"), .quitApp("Notes"), .shell("pwd"), .window("left")]
        let restored = try JSONDecoder().decode([Action].self, from: JSONEncoder().encode(actions))
        XCTAssertEqual(restored, actions)
        XCTAssertTrue(CommandPlan(transcript: "Recovery", actions: restored, requiresReview: true).needsConfirmation)
        XCTAssertTrue(restored[2].needsConfirmation)
        XCTAssertTrue(restored[3].needsConfirmation)
    }

    func testHorizontalNotchAndLegacyProfiles() throws {
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
        var config = NotchConfiguration()
        let bar = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: config)
        XCTAssertEqual(bar.frame.minX, screen.minX + 8)
        XCTAssertEqual(bar.frame.maxX, screen.maxX - 8)
        XCTAssertEqual(bar.frame.height, 38 + 132 + NotchGeometry.horizontalControlsHeight)
        for rowHeight in [120.0, 260.0] {
            var sized = config
            sized.horizontalHeight = rowHeight
            let layout = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: sized)
            XCTAssertEqual(layout.frame.height - layout.headerHeight - NotchGeometry.horizontalControlsHeight, rowHeight - 28)
        }
        let collapsed = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: false, configuration: config)
        XCTAssertEqual(collapsed.frame.width, 190 + config.wingWidth * 2)
        XCTAssertEqual(collapsed.frame.height, 46)
        config.fullWidthExpansion = false; config.expandedWidth = 900
        let custom = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: config)
        XCTAssertEqual(custom.frame.width, 900)
        config.expansionLayout = .vertical; config.contentHeight = 400
        let vertical = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: config)
        XCTAssertEqual(vertical.frame.height, 438)
        config.accentHex = "79D5FF"
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        for key in ["expansionLayout", "fullWidthExpansion", "horizontalHeight"] { legacy.removeValue(forKey: key) }
        legacy["sectionOrder"] = ["voice", "shortcuts", "workflows", "activity", "clock", "timer", "notes"]
        let migrated = try NotchConfiguration.profile(JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated.expansionLayout, .horizontal)
        XCTAssertTrue(migrated.fullWidthExpansion)
        XCTAssertEqual(migrated.horizontalHeight, 160)
        XCTAssertEqual(migrated.accentHex, config.accentHex)
        XCTAssertEqual(migrated.shortcuts, config.shortcuts)
        XCTAssertTrue(migrated.visibleSections.contains(.media))
    }

    func testNotchMotionStaysCameraSafe() {
        let start = CGRect(x: 600, y: 940, width: 300, height: 42)
        let end = CGRect(x: 500, y: 540, width: 500, height: 442)
        for opening in [true, false] {
            XCTAssertEqual(NotchMotion.frame(from: start, to: end, progress: 0, opening: opening), start)
            XCTAssertEqual(NotchMotion.frame(from: start, to: end, progress: 1, opening: opening), end)
            var previous: Double = -1
            for sample in 0...20 {
                let progress = Double(sample) / 20
                let eased = NotchMotion.progress(progress, opening: opening)
                XCTAssertTrue(eased >= previous && eased <= 1)
                previous = eased
                let frame = NotchMotion.frame(from: start, to: end, progress: progress, opening: opening)
                XCTAssertTrue(abs(frame.maxY - start.maxY) < 0.00001)
                XCTAssertTrue(abs(frame.midX - start.midX) < 0.00001)
                XCTAssertTrue(frame.width >= start.width && frame.width <= end.width)
            }
        }
        XCTAssertEqual(NotchMotion.progress(-10, opening: true), 0)
        XCTAssertEqual(NotchMotion.progress(10, opening: true), 1)
        XCTAssertEqual(NotchMotion.progress(.nan, opening: false), 1)
    }

    func testMacControlPermissionPreflight() throws {
        let protected: [Action] = [.typeText("hi"), .shortcut("command c"), .click("Save"), .clickNumber(1), .showNumbers, .scroll("down", 3), .window("left"), .lock]
        for action in protected { XCTAssertTrue(action.requiresAccessibility, action.summary) }
        let independent: [Action] = [.openApp("Safari"), .quitApp("Safari"), .openURL("https://apple.com"), .search("test"), .hideNumbers, .volume(20), .mute(true), .screenshot, .sleep, .reveal("~/Downloads"), .shell("pwd"), .wait(1)]
        for action in independent { XCTAssertFalse(action.requiresAccessibility, action.summary) }
        let plan = try WorkflowResolver().expand(parser.parse("run focus"), workflows: [Workflow(name: "focus", commands: "open Safari\nleft half\nopen Notes\nright half")])
        XCTAssertTrue(plan.requiresAccessibility)
        XCTAssertFalse(try parser.parse("open Safari then volume 25").requiresAccessibility)
        XCTAssertEqual(ControlPermission.paneName(macOSMajorVersion: 26), "Accessibility")
        XCTAssertEqual(ControlPermission.paneName(macOSMajorVersion: 27), "Device Control and Data Access")
    }

    func testScreenGuidanceValidation() throws {
        let valid = #"{"answer":"Click the toolbar button.","highlights":[{"x":0.1,"y":0.2,"width":0.15,"height":0.08,"label":"Toolbar"}]}"#
        let guide = try JSONDecoder().decode(GuidanceResult.self, from: Data(valid.utf8)).validated()
        XCTAssertEqual(guide.highlights.count, 1)
        XCTAssertTrue(guide.highlights[0].valid)
        for rectangle in [
            #"{"x":-0.1,"y":0,"width":0.2,"height":0.1,"label":"bad"}"#,
            #"{"x":0.9,"y":0,"width":0.2,"height":0.1,"label":"bad"}"#,
            #"{"x":0,"y":0,"width":0,"height":0.1,"label":"bad"}"#,
            #"{"x":0,"y":0,"width":0.2,"height":0.1,"label":""}"#
        ] {
            let data = Data(("{\"answer\":\"Test\",\"highlights\":[" + rectangle + "]}").utf8)
            let result = try JSONDecoder().decode(GuidanceResult.self, from: data)
            XCTAssertThrowsError(try result.validated())
        }
        let many = "{\"answer\":\"Test\",\"highlights\":[" + Array(repeating: #"{"x":0.1,"y":0.1,"width":0.1,"height":0.1,"label":"Test"}"#, count: 9).joined(separator: ",") + "]}"
        let tooMany = try JSONDecoder().decode(GuidanceResult.self, from: Data(many.utf8))
        XCTAssertThrowsError(try tooMany.validated())
    }

    func testDictationStopDoesNotEatOrdinaryText() {
        XCTAssertTrue(DictationControl.shouldStop("Newt, stop dictation"))
        XCTAssertTrue(DictationControl.shouldStop("hey new, stop dictating."))
        XCTAssertTrue(DictationControl.shouldStop("Computer stop listening", custom: "Computer"))
        XCTAssertFalse(DictationControl.shouldStop("please write stop dictation in the document"))
        XCTAssertFalse(DictationControl.shouldStop("newton stop dictation"))
        XCTAssertFalse(DictationControl.shouldStop("Newt stop dictation", custom: "Computer"))
    }

    func testNotchWrappingGrid() {
        let sections = NotchSection.allCases.count
        for width in [304.0, 900.0, 1460.0, 2242.0] {
            let grid = NotchGridGeometry.calculate(width: width, sectionCount: sections, rowHeight: 132)
            XCTAssertTrue(grid.columns >= 1)
            XCTAssertTrue(grid.rows * grid.columns >= sections)
            XCTAssertTrue((grid.rows - 1) * grid.columns < sections)
            XCTAssertTrue(CGFloat(grid.columns) * grid.cardWidth + CGFloat(grid.columns - 1) * NotchGridGeometry.spacing <= width + 0.001)
            XCTAssertEqual(grid.minimumHeight, CGFloat(grid.rows) * 132 + CGFloat(grid.rows - 1) * 12)
        }
        let wrapped = NotchGridGeometry.calculate(width: 2242, sectionCount: 11, rowHeight: 132)
        XCTAssertEqual(wrapped.columns, 8)
        XCTAssertEqual(wrapped.rows, 2)
        let empty = NotchGridGeometry.calculate(width: 800, sectionCount: 0, rowHeight: 132)
        XCTAssertEqual(empty.minimumHeight, 0)
        var configuration = NotchConfiguration()
        configuration.hiddenSections = []
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let layout = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: configuration)
        XCTAssertEqual(layout.frame.height, 38 + 132 * 4 + 12 * 3 + NotchGeometry.horizontalControlsHeight)
        let measured = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: configuration, measuredGridHeight: 750)
        XCTAssertEqual(measured.frame.height, 38 + 750 + NotchGeometry.horizontalControlsHeight)
        let bounded = NotchGeometry.calculate(screen: screen, hardwareWidth: 190, hardwareHeight: 38, expanded: true, configuration: configuration, measuredGridHeight: 2000)
        XCTAssertTrue(bounded.frame.minY >= screen.minY + 16)
    }

    func testInstalledAppMatching() throws {
        let insiders = InstalledApplication(name: "Code - Insiders", bundleID: "com.microsoft.VSCodeInsiders", path: "/Applications/Visual Studio Code - Insiders.app")
        let stable = InstalledApplication(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", path: "/Applications/Visual Studio Code.app")
        let safari = InstalledApplication(name: "Safari", bundleID: "com.apple.Safari", path: "/System/Applications/Safari.app")
        let settings = InstalledApplication(name: "System Settings", bundleID: "com.apple.systempreferences", path: "/System/Applications/System Settings.app")
        for name in ["vscode", "VS Code", "insider", "insiders", "code insiders", "Visual Studio Code - Insiders.app", insiders.path, insiders.bundleID] {
            XCTAssertEqual(try ApplicationMatch.resolve(name, in: [safari, insiders]), insiders)
        }
        XCTAssertEqual(try ApplicationMatch.resolve("vscode", in: [insiders, stable]), stable)
        XCTAssertEqual(try ApplicationMatch.resolve("insider", in: [stable, insiders]), insiders)
        XCTAssertEqual(try ApplicationMatch.resolve("settings", in: [safari, settings]), settings)
        XCTAssertEqual(try ApplicationMatch.resolve("SAFARI.app", in: [safari]), safari)
        XCTAssertThrowsError(try ApplicationMatch.resolve("saf", in: [safari]))
        XCTAssertThrowsError(try ApplicationMatch.resolve("all apps in the applications folder", in: [safari, insiders]))
        XCTAssertThrowsError(try ApplicationMatch.resolve("", in: [safari]))
        let duplicate = InstalledApplication(name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app")
        XCTAssertThrowsError(try ApplicationMatch.resolve("Safari", in: [safari, duplicate]))
        XCTAssertThrowsError(try ApplicationMatch.resolve("com.apple.Safari", in: [safari, duplicate]))
        XCTAssertEqual(try ApplicationMatch.resolve(safari.path, in: [safari, duplicate]), safari)
        let unicode = InstalledApplication(name: "Café Notes", bundleID: "test.notes", path: "/Applications/Café Notes.app")
        XCTAssertEqual(try ApplicationMatch.resolve("cafe notes", in: [unicode]), unicode)
    }

    func testAcousticSpeechEndpoint() throws {
        var endpoint = SpeechEndpoint(now: 0)
        XCTAssertEqual(endpoint.state(now: 0), .waiting)
        for sample in 1...30 {
            let time = Double(sample) / 10
            endpoint.observe(powerDB: -25, now: time)
            if sample == 4 { endpoint.transcriptChanged(now: time) }
            // A stalled transcript must not dispatch while the microphone still hears speech.
            if sample > 2 { XCTAssertEqual(endpoint.state(now: time), .speaking) }
        }
        endpoint.observe(powerDB: -75, now: 3.1)
        XCTAssertEqual(endpoint.state(now: 4.2), .pausing)
        endpoint.transcriptChanged(now: 4.3)
        XCTAssertEqual(endpoint.state(now: 4.5), .pausing)
        XCTAssertEqual(endpoint.state(now: 5.8), .finished)

        var resumed = SpeechEndpoint(silenceDuration: 1.4, now: 0)
        for sample in 1...8 { resumed.observe(powerDB: -26, now: Double(sample) / 10) }
        resumed.observe(powerDB: -75, now: 0.9)
        XCTAssertEqual(resumed.state(now: 1.9), .pausing)
        for sample in 20...26 { resumed.observe(powerDB: -26, now: Double(sample) / 10) }
        XCTAssertEqual(resumed.state(now: 2.6), .speaking)
        resumed.observe(powerDB: -75, now: 2.7)
        XCTAssertEqual(resumed.state(now: 3.9), .pausing)
        XCTAssertEqual(resumed.state(now: 4.1), .finished)

        var noise = SpeechEndpoint(now: 0)
        noise.observe(powerDB: -20, now: 0.05)
        noise.observe(powerDB: -75, now: 0.1)
        XCTAssertFalse(noise.hasSpeech)
        XCTAssertEqual(noise.state(now: 2), .waiting)
        XCTAssertEqual(noise.state(now: 12), .idleTimeout)
        XCTAssertEqual(noise.state(now: 180), .durationLimit)
        noise.observe(powerDB: .nan, now: 2)
        noise.observe(powerDB: -20, now: .nan)
        XCTAssertFalse(noise.hasSpeech)
        XCTAssertEqual(SpeechEndpoint(silenceDuration: .nan, now: 0).silenceDuration, 1.4)
        XCTAssertEqual(SpeechEndpoint(silenceDuration: 0.1, now: 0).silenceDuration, 0.6)
        XCTAssertEqual(SpeechEndpoint(silenceDuration: 100, now: 0).silenceDuration, 3)

        var slow = SpeechEndpoint(silenceDuration: 3, now: 0)
        for sample in 1...10 { slow.observe(powerDB: -26, now: Double(sample) / 10) }
        slow.observe(powerDB: -75, now: 1.1)
        XCTAssertEqual(slow.state(now: 3.9), .pausing)
        XCTAssertEqual(slow.state(now: 4.1), .finished)
    }

    func testGeminiProviderTranslation() throws {
        let schema: [String: Any] = ["type": "object", "properties": ["commands": ["type": "array", "items": ["type": "string"]]], "required": ["commands"]]
        let body: [String: Any] = ["model": "gemini-2.5-flash", "instructions": "Keep review required", "max_output_tokens": 2000,
            "input": [["role": "assistant", "content": "Earlier reply"], ["role": "user", "content": [["type": "input_text", "text": "Explain"], ["type": "input_image", "image_url": "data:image/jpeg;base64,YQ=="]]]],
            "text": ["format": ["schema": schema]]]
        let converted = try GeminiPayload.request(body)
        let turns = converted["contents"] as? [[String: Any]] ?? []
        XCTAssertEqual(turns.first?["role"] as? String, "model")
        XCTAssertEqual(turns.last?["role"] as? String, "user")
        let parts = turns.last?["parts"] as? [[String: Any]] ?? []
        XCTAssertEqual((parts.last?["inlineData"] as? [String: String])?["mimeType"], "image/jpeg")
        let config = converted["generationConfig"] as? [String: Any] ?? [:]
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
        XCTAssertTrue(config["responseJsonSchema"] != nil)
        XCTAssertTrue(converted["tools"] == nil)
        let search = try GeminiPayload.request(["input": "Find source", "tools": [["type": "web_search"]]])
        XCTAssertTrue(search["tools"] != nil)
        let audio = try GeminiPayload.request(["input": [["role": "user", "content": [["type": "input_audio", "data": "YQ=="]]]]])
        XCTAssertTrue(audio["contents"] != nil)
        XCTAssertThrowsError(try GeminiPayload.request(["input": [["role": "user", "content": [["type": "input_image", "image_url": "https://example.com/private"]]]]]))
        let candidate: [String: Any] = ["finishReason": "STOP", "content": ["parts": [["text": "hidden reasoning", "thought": true], ["text": "Visible answer"]]], "groundingMetadata": ["groundingChunks": [["web": ["uri": "https://example.com/source", "title": "Source"]], ["web": ["uri": "javascript:alert(1)", "title": "Bad"]]]]]
        let data = try JSONSerialization.data(withJSONObject: ["candidates": [candidate]])
        let text = try GeminiPayload.response(data).text(markdown: true)
        XCTAssertTrue(text.contains("Visible answer"))
        XCTAssertTrue(text.contains("](https://example.com/source)"))
        XCTAssertFalse(text.contains("hidden reasoning"))
        XCTAssertFalse(text.contains("javascript:"))
        for reason in ["MAX_TOKENS", "SAFETY", "RECITATION"] {
            XCTAssertThrowsError(try GeminiPayload.response(JSONSerialization.data(withJSONObject: ["candidates": [["finishReason": reason, "content": ["parts": [["text": "partial"]]]]]])))
        }
        XCTAssertThrowsError(try GeminiPayload.response(Data("{}".utf8)))
        XCTAssertEqual(AIProvider.gemini.defaultModel, "gemini-2.5-flash")
        XCTAssertTrue(AIProvider.gemini.keyFlag != AIProvider.openAI.keyFlag)
    }

    func testOAuthBoundaries() throws {
        XCTAssertEqual(OAuthFlow.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let first = try OAuthFlow.randomToken(), second = try OAuthFlow.randomToken()
        XCTAssertEqual(first.count, 43)
        XCTAssertTrue(first != second)
        XCTAssertEqual(try OAuthFlow.callback("/oauth?code=a%2Bb&state=expected", state: "expected"), "a+b")
        for target in ["/oauth?code=a&state=wrong", "/oauth?code=a&state=expected&state=expected", "/oauth?code=a&code=b&state=expected", "/oauth?error=denied&state=expected", "https://evil.test/oauth?code=a&state=expected", "/other?code=a&state=expected"] {
            XCTAssertThrowsError(try OAuthFlow.callback(target, state: "expected"))
        }
        let form = String(decoding: OAuthFlow.form(["code": "a+b&c=d", "text": "hello world"]), as: UTF8.self)
        XCTAssertTrue(form.contains("a%2Bb%26c%3Dd"))
        XCTAssertTrue(form.contains("hello%20world"))
    }

    func testConversationContextBoundsAndModes() throws {
        let turn = ConversationTurn(role: "user", content: String(repeating: "a", count: 20000))
        XCTAssertEqual(turn.content.count, 12000)
        XCTAssertEqual(try JSONDecoder().decode(ConversationTurn.self, from: JSONEncoder().encode(turn)), turn)
        XCTAssertEqual(Set(AssistantMode.allCases.map(\.rawValue)), Set(["command", "talk", "guide", "dictate", "agent"]))
    }
}

@main
struct CoreChecks {
    static func main() {
        let suite = CommandTests()
        let cases: [(String, () throws -> Void)] = [
            ("chained commands", suite.testChainedCommands),
            ("literal text boundaries", suite.testLiteralTextCannotBecomeActions),
            ("Unicode preservation", suite.testPreservesCaseAndUnicode),
            ("spoken numbers", suite.testSpeechNumbers),
            ("label clicks", suite.testLabelClicks),
            ("numeric bounds", suite.testBounds),
            ("empty and unknown commands", suite.testEmptyAndUnknown),
            ("URLs and apps", suite.testURLsAndApps),
            ("risk classification", suite.testRiskClassification),
            ("shortcuts and scrolling", suite.testShortcutAndScroll),
            ("workflow expansion", suite.testWorkflowExpansion),
            ("nested risk propagation", suite.testWorkflowRiskCannotBeHidden),
            ("cycle rejection", suite.testCyclesAreRejected),
            ("unknown and empty workflows", suite.testUnknownAndEmptyWorkflows),
            ("step limits", suite.testStepLimits),
            ("workflow persistence encoding", suite.testWorkflowCodableRoundTrip),
            ("model review requirement", suite.testModelPlansAlwaysRequireReview),
            ("model shell rejection", suite.testModelsCannotGenerateShellDirectlyOrViaWorkflow),
            ("empty model plan", suite.testEmptyModelPlanIsRejected),
            ("Newt and New wake phrases", suite.testRenamedWakePhrase),
            ("custom wake phrase", suite.testCustomWakePhrase),
            ("OpenAI output and inline citations", suite.testOpenAIOutputAndCitations),
            ("incomplete and refused responses", suite.testOpenAIRejectsIncompleteAndRefusal),
            ("unsafe citation URLs", suite.testUnsafeAndInvalidCitationIgnored),
            ("OpenAI action review", suite.testOpenAIActionDecisionsStillNeedReview),
            ("notch profile serialization and bounds", suite.testNotchProfileRoundTripAndLimits),
            ("notch module and button normalization", suite.testNotchShortcutAndSectionNormalization),
            ("notch camera clearance and display geometry", suite.testNotchGeometryProtectsCutoutAndScreenEdges),
            ("routine missed runs, DST, persistence, and approval", suite.testRoutineCoalescingAndReview),
            ("browser context freshness and URL boundaries", suite.testBrowserContextBoundaries),
            ("diagram bounded scene data", suite.testDiagramValidation),
            ("audio multipart and multilingual transcripts", suite.testAudioMultipartAndTranscript),
            ("timed lyric parsing", suite.testTimedLyrics),
            ("recovery persistence preserves action risk", suite.testRecoveryActionsPersistWithoutChangingRisk),
            ("horizontal notch and saved profile migration", suite.testHorizontalNotchAndLegacyProfiles),
            ("notch animation bounds and camera safety", suite.testNotchMotionStaysCameraSafe),
            ("Mac control permission preflight", suite.testMacControlPermissionPreflight),
            ("screen guidance coordinate validation", suite.testScreenGuidanceValidation),
            ("dictation stop phrase boundaries", suite.testDictationStopDoesNotEatOrdinaryText),
            ("OAuth PKCE, state and encoding boundaries", suite.testOAuthBoundaries),
            ("Gemini multimodal schema, grounding and refusal handling", suite.testGeminiProviderTranslation),
            ("acoustic speech endpoints, pauses, noise, and timeouts", suite.testAcousticSpeechEndpoint),
            ("installed app aliases, exact identities and ambiguity", suite.testInstalledAppMatching),
            ("notch wraps all modules into rows and grows down", suite.testNotchWrappingGrid),
            ("conversation context bounds and modes", suite.testConversationContextBoundsAndModes)
        ]
        for (name, test) in cases {
            let before = failures.count
            do { try test() } catch { failures.append("\(name): \(error)") }
            print("\(failures.count == before ? "PASS" : "FAIL") \(name)")
        }
        for failure in failures { fputs(failure + "\n", stderr) }
        print("\(cases.count) groups, \(assertions) assertions, \(failures.count) failures")
        exit(failures.isEmpty ? 0 : 1)
    }
}

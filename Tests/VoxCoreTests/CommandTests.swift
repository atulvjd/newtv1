import Foundation
import VoxCore

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
        for value in ["", "   ", "destroy everything", "open ", "open Safari then "] { XCTAssertThrowsError(try parser.parse(value)) }
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
            ("empty model plan", suite.testEmptyModelPlanIsRejected)
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

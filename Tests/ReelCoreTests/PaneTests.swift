import AVFoundation
import Foundation
@testable import ReelCore
import Testing

private let dir = URL(fileURLWithPath: "/tmp/demos", isDirectory: true)

private func parse(_ text: String) throws -> Tape {
    try Tape.parse(text, relativeTo: dir)
}

private func failure(_ text: String) -> TapeError? {
    do {
        _ = try parse(text)
        return nil
    } catch {
        return error as? TapeError
    }
}

struct PaneParsingTests {
    @Test func movingBetweenFiles() throws {
        let tape = try parse("""
        Screen code
        Output a.mp4
        Code A.swift
        Code@slide-left,ease-out,500ms B.swift at "func b"
        Peek "helper()" C.swift lines 3-9 at "func helper"
        Peek off
        Split D.swift at line 4
        Pane left
        Pane right
        Link "protocol P" -> "struct S: P" "conforms to"
        Link "a" -> "b"
        Link off
        Split off
        """)
        let file = { (name: String) in URL(fileURLWithPath: "/tmp/demos/\(name)") }
        #expect(tape.steps.map(\.command) == [
            .code(CodeFile(url: file("A.swift"), lines: nil, at: nil), transition: nil),
            .code(
                CodeFile(url: file("B.swift"), lines: nil, at: .text("func b")),
                transition: SectionTransition(kind: .slideLeft, easing: .easeOut, duration: .milliseconds(500))
            ),
            .peek("helper()", file: CodeFile(url: file("C.swift"), lines: 3 ... 9, at: .text("func helper"))),
            .peek(nil, file: nil),
            .split(CodeFile(url: file("D.swift"), lines: nil, at: .line(4))),
            .pane(0),
            .pane(1),
            .link("protocol P", to: "struct S: P", label: "conforms to"),
            .link("a", to: "b", label: nil),
            .link(nil, to: nil, label: nil),
            .split(nil),
        ])
        // All of it is drawn into the take.
        #expect(tape.actions.count == tape.steps.count)
    }

    @Test(arguments: [
        ("Screen code\nOutput a.mp4\nPane middle", 3, "expected Pane left or Pane right"),
        ("Screen code\nOutput a.mp4\nSplit", 3, "expected Split <file> [lines <a>-<b>] [at line <n> | at \"<text>\"]"),
        (
            "Screen code\nOutput a.mp4\nPeek A.swift", 3,
            "expected Peek \"<text>\" <file> [lines <a>-<b>] [at line <n> | at \"<text>\"] or Peek off"
        ),
        (
            "Screen code\nOutput a.mp4\nPeek \"a\"", 3,
            "expected Peek \"<text>\" <file> [lines <a>-<b>] [at line <n> | at \"<text>\"]"
        ),
        (
            "Screen code\nOutput a.mp4\nLink \"a\" \"b\"",
            3,
            "expected Link \"<text>\" -> \"<text>\" [\"<label>\"] or Link off"
        ),
        (
            "Screen code\nOutput a.mp4\nLink \"a\" -> b",
            3,
            "expected Link \"<text>\" -> \"<text>\" [\"<label>\"] or Link off"
        ),
        (
            "Screen terminal\nOutput a.mp4\nSplit A.swift",
            3,
            "Split is for a code screen: start the reel with Screen code"
        ),
        (
            "Launch x\nOutput a.mp4\nLink \"a\" -> \"b\"",
            3,
            "Link is for a code screen: start the reel with Screen code"
        ),
        ("Screen code\nOutput a.mp4\nGo@crossfade line 3", 3, "Go takes no @option"),
    ] as [(String, Int, String)])
    func refusals(text: String, line: Int, message: String) {
        #expect(failure(text) == TapeError(line: line, message: message))
    }
}

/// Draws the code screen's panes for real: no permission needed.
@Suite(.serialized)
struct PaneDrawingTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-panes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try """
        protocol Synthesizer {
            func speak(_ text: String) -> Clip
        }
        """.write(to: folder.appending(path: "Synthesizer.swift"), atomically: true, encoding: .utf8)
        try """
        struct Voicebox: Synthesizer {
            func speak(_ text: String) -> Clip {
                Clip(id: profileID())
            }

            func profileID() -> String {
                "main"
            }
        }
        """.write(to: folder.appending(path: "Voicebox.swift"), atomically: true, encoding: .utf8)
    }

    private func file(_ name: String, at: CodeAnchor? = nil) throws -> [String: Any] {
        try Recorder.screenFile(CodeFile(url: folder.appending(path: name), lines: nil, at: at))
    }

    @Test @MainActor func splitPeekAndLinkOnThePage() async throws {
        let page = try await ScreenPage(
            "screen.html", size: CGSize(width: 1280, height: 720), options: ["fontSize": 16, "peekLines": 8]
        )
        func run(_ body: String, _ arguments: [String: Any] = [:]) async throws -> String? {
            let problem = try await page.call(body, arguments) as? String
            for _ in 0 ..< 40 {
                _ = try await page.pump(20)
            }
            return problem
        }
        func number(_ script: String) async throws -> Double {
            try #require(try await page.call("return \(script)") as? Double)
        }
        #expect(try await run("return await reelScreen.open(f, null)", ["f": file("Synthesizer.swift")]) == nil)
        #expect(try await run("return reelScreen.pane(1)") == "there is no right pane: Split a file first")

        // A file that slides in: halfway, the one before is moving out to the left and the new one in from the right.
        _ = try await page.call(
            "return await reelScreen.open(f, {kind: 'slide-left', easing: 'linear', ms: 400})",
            ["f": file("Voicebox.swift")]
        )
        _ = try await page.pump(200)
        #expect(try await page.call("return document.querySelector('.content').style.transform") as? String
            == "translateX(50%)")
        #expect(try await page.call("return document.querySelector('.leaving').style.transform") as? String
            == "translateX(-50%)")
        _ = try await page.pump(250)
        #expect(try await number("document.querySelectorAll('.leaving').length") == 0)
        #expect(try await run("return await reelScreen.open(f, {kind: 'cut', easing: 'linear', ms: 0})", [
            "f": file("Synthesizer.swift"),
        ]) == nil)

        // A peek opens a box under the line, an editor with the other file in it, and closes again.
        #expect(try await run("return await reelScreen.peek('speak', f)", ["f": file("Voicebox.swift")]) == nil)
        #expect(try await number("document.querySelectorAll('.peek .monaco-editor').length") == 1)
        #expect(try await number("document.querySelector('.peek').offsetHeight") > 100)
        #expect(try await run("return reelScreen.peek(null, null)") == nil)
        #expect(try await number("document.querySelectorAll('.peek').length") == 0)
        #expect(try await run("return await reelScreen.peek('nowhere', f)", ["f": file("Voicebox.swift")])
            == "\"nowhere\" is not in Synthesizer.swift")

        // Split: two panes of half the width each, the right one active.
        #expect(try await run(
            "return await reelScreen.split(f)",
            ["f": file("Voicebox.swift", at: .text("func speak"))]
        )
            == nil)
        #expect(try await number("document.querySelectorAll('.pane').length") == 2)
        #expect(try await number("document.querySelectorAll('.pane')[1].offsetLeft") == 640)
        #expect(try await number("document.querySelectorAll('.pane')[0].offsetWidth") == 640)
        #expect(try await run("return await reelScreen.split(f)", ["f": file("Voicebox.swift")])
            == "the screen is already split; Split off first")
        // The caret is the right pane's: its x is past the middle.
        let (_, caret) = try await page.pump(20)
        #expect(try #require(caret).x > 640)

        // A link draws an arrow from the left pane to the right one, its label with it.
        #expect(try await run("return reelScreen.link('protocol Synthesizer', 'struct Voicebox', 'conforms to')")
            == nil)
        let path = try #require(try await page
            .call("return document.querySelector('#links path:not([d^=\"M 0 1\"])').getAttribute('d')") as? String)
        let points = path.split(separator: " ").compactMap { Double($0.trimmingCharacters(in: .punctuationCharacters)) }
        #expect(points.first! < 640 && points[points.count - 2] > 640, "\(path)")
        #expect(try await page.call("return document.querySelector('#links .label text').textContent") as? String
            == "conforms to")
        #expect(try await run("return reelScreen.link('protocol Synthesizer', 'struct Nothing', null)")
            == "\"struct Nothing\" is not on the screen")

        // Split off: one pane again, the links into the right one gone.
        #expect(try await run("return await reelScreen.split(null)") == nil)
        #expect(try await number("document.querySelectorAll('.pane').length") == 1)
        #expect(try await number("document.querySelectorAll('#links g').length") == 0)
        #expect(try await number("document.querySelector('.pane').offsetWidth") == 1280)
    }

    @Test func theSameMovesDrawTheSameTake() async throws {
        let script = """
        Screen code
        Set Viewport 640x360
        Set FrameRate 30
        Output a.mp4
        Code Synthesizer.swift
        Code@slide-left,300ms Voicebox.swift
        Peek "profileID()" Voicebox.swift at "func profileID"
        Peek off
        Code@crossfade,300ms Synthesizer.swift
        Split Voicebox.swift
        Link "protocol Synthesizer" -> "Voicebox: Synthesizer" "conforms to"
        Pane left
        Mark "speak" 1
        Split off
        """
        var takes: [(Take, [Data])] = []
        for name in ["one", "two"] {
            let url = folder.appending(path: "\(name).reel")
            try script.write(to: url, atomically: true, encoding: .utf8)
            let location = TakeLocation(tape: url)
            let take = try await Recorder.record(Tape.parse(script, relativeTo: folder), into: location, log: { _ in })
            try await takes.append((take, movieFrames(AVURLAsset(url: location.movie))))
        }
        #expect(takes[0].0 == takes[1].0)
        #expect(takes[0].1.count == takes[1].1.count)
        #expect(takes[0].1.count > 30, "a frame for each moment something moved")
        for (index, (a, b)) in zip(takes[0].1, takes[1].1).enumerated() {
            #expect(frameDifference(a, b) < 0.5, "frame \(index) differs by \(frameDifference(a, b))")
        }
    }
}

import Foundation
@testable import ReelCore
import Testing

private let dir = URL(fileURLWithPath: "/tmp/demos", isDirectory: true)

private func failure(_ text: String) -> TapeError? {
    do {
        _ = try Tape.parse(text, relativeTo: dir)
        return nil
    } catch {
        return error as? TapeError
    }
}

struct DiffParsingTests {
    @Test func diffs() throws {
        let tape = try Tape.parse("""
        Screen code
        Output a.mp4
        Diff before.swift after.swift
        Diff@slide-left,400ms Clock.swift since HEAD~1 at hunk 2
        Go hunk 3
        Go line 12
        """, relativeTo: dir)
        let file = { (name: String) in URL(fileURLWithPath: "/tmp/demos/\(name)") }
        #expect(tape.steps.map(\.command) == [
            .diff(
                DiffSource(before: .file(file("before.swift")), after: file("after.swift"), at: nil),
                transition: nil
            ),
            .diff(
                DiffSource(before: .revision("HEAD~1"), after: file("Clock.swift"), at: .hunk(2)),
                transition: SectionTransition(kind: .slideLeft, easing: .easeInOut, duration: .milliseconds(400))
            ),
            .go(.hunk(3)),
            .go(.line(12)),
        ])
    }

    @Test(arguments: [
        (
            "Screen code\nOutput a.mp4\nDiff only.swift", 3,
            "expected Diff[@<transition>] <before> <after> or Diff[@<transition>] <file> since <revision>, "
                + "then [at line <n> | at hunk <n> | at \"<text>\"]"
        ),
        (
            "Screen code\nOutput a.mp4\nDiff a.swift since", 3,
            "expected Diff[@<transition>] <before> <after> or Diff[@<transition>] <file> since <revision>, "
                + "then [at line <n> | at hunk <n> | at \"<text>\"]"
        ),
        (
            "Screen code\nOutput a.mp4\nGo hunk",
            3,
            "a place in the code is line <n>, hunk <n> or some text to find, in quotes"
        ),
        ("Screen terminal\nOutput a.mp4\nDiff a b", 3, "Diff is for a code screen: start the reel with Screen code"),
    ] as [(String, Int, String)])
    func refusals(text: String, line: Int, message: String) {
        #expect(failure(text) == TapeError(line: line, message: message))
    }
}

@Suite(.serialized)
struct DiffDrawingTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func aRevisionIsReadFromGit() throws {
        let clock = try write("Clock.swift", "struct Clock {\n    var end = 0.0\n}\n")
        _ = try Recorder.git(["init", "-q"], in: folder)
        _ = try Recorder.git(["add", "Clock.swift"], in: folder)
        _ = try Recorder.git(
            ["-c", "user.name=reel", "-c", "user.email=reel@example.com", "commit", "-q", "-m", "first"], in: folder
        )
        try "struct Clock {\n    var end = 0.0\n    var markers: [String: Double] = [:]\n}\n"
            .write(to: clock, atomically: true, encoding: .utf8)
        let page = try Recorder.screenDiff(DiffSource(before: .revision("HEAD"), after: clock, at: nil))
        let diff = try #require(page["diff"] as? [String: Any])
        #expect(diff["kinds"] as? [String] == ["kept", "kept", "added", "kept"])
        #expect(diff["added"] as? Int == 1 && diff["removed"] as? Int == 0)
        let label = try #require(diff["label"] as? String)
        #expect(label.hasPrefix("since HEAD ("), "\(label)")
        #expect(throws: ReelError.self) {
            try Recorder.screenDiff(DiffSource(before: .revision("nowhere"), after: clock, at: nil))
        }
    }

    @Test @MainActor func aDiffOnThePage() async throws {
        let before = try write("before.swift", "let a = 1\nlet b = 2\nlet c = 3\nreturn nil\n")
        let after = try write("after.swift", "let a = 1\nlet b = 20\nlet c = 3\nlet d = 4\nreturn d\n")
        let page = try await ScreenPage(
            "screen.html", size: CGSize(width: 1000, height: 560), options: ["fontSize": 16, "peekLines": 8]
        )
        func run(_ body: String, _ arguments: [String: Any] = [:]) async throws -> String? {
            let problem = try await page.call(body, arguments) as? String
            for _ in 0 ..< 30 {
                _ = try await page.pump(20)
            }
            return problem
        }
        func count(_ selector: String) async throws -> Int {
            try #require(try await page.call("return document.querySelectorAll('\(selector)').length") as? Int)
        }
        let diff = try Recorder.screenDiff(DiffSource(before: .file(before), after: after, at: nil))
        #expect(try await run("return await reelScreen.open(f, null)", ["f": diff]) == nil)
        // b's line edited, d added, nil replaced: two removed lines, three added, and the 2 in 20 marked.
        #expect(try await count(".diff-added") == 3)
        #expect(try await count(".diff-removed") == 2)
        #expect(try await page.call("return document.querySelector('.diff-word-added').textContent") as? String == "20")
        #expect(try await page
            .call("return document.querySelector('.header .stat.added').textContent") as? String == "+3")
        #expect(try await page.call("return document.querySelector('.header .since').textContent") as? String
            == "before.swift → after.swift")
        // Places are the new file's: line 4 is `let d = 4`, which comes after two removed lines.
        #expect(try await run("return reelScreen.go({line: 4})") == nil)
        let row = try #require(try await page.call(
            "return document.querySelector('.caret').style.top"
        ) as? String)
        // Hunk 2 starts at its first change: the removed `return nil`, the row above.
        #expect(try await run("return reelScreen.go({hunk: 2})") == nil)
        let hunk = try #require(try await page.call("return document.querySelector('.caret').style.top") as? String)
        #expect(Double(hunk.dropLast(2))! + 24 == Double(row.dropLast(2))!, "\(hunk) then \(row)")
        #expect(try await run("return reelScreen.go({hunk: 3})") == "after.swift has 2 hunks, not 3")
        #expect(try await run("return reelScreen.focus([2, 4])") == nil)
        // A file that is not a diff has no hunks.
        let plain = try Recorder.screenFile(CodeFile(url: after, lines: nil, at: nil))
        #expect(try await run("return await reelScreen.open(f, null)", ["f": plain]) == nil)
        #expect(try await run("return reelScreen.go({hunk: 1})") == "after.swift is not a diff, so it has no hunk 1")
        #expect(try await count(".diff-added") == 0)
    }
}

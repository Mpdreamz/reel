import AVFoundation
import Foundation
@testable import ReelCore
import Testing

/// A folder with a file to show and a track in a file of its own.
private struct Folder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "reel-tracks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "struct A {\n    let x = 1\n}\n".write(
            to: url.appending(path: "A.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "Screen code\nSet Viewport 480x270\nCode A.swift\nMark \"let x\" 1 as marked\n"
            .write(to: url.appending(path: "script.reel"), atomically: true, encoding: .utf8)
    }

    func parse(_ text: String) throws -> Tape {
        try Tape.parse(text, relativeTo: url)
    }

    func failure(_ text: String) -> TapeError? {
        do {
            _ = try parse(text)
            return nil
        } catch {
            return error as? TapeError
        }
    }
}

struct TrackParsingTests {
    @Test func tracksInlineAndInFiles() throws {
        let folder = try Folder()
        let tape = try folder.parse("""
        Screen terminal as term
          Set Columns 50
          Type "echo hi"

          Key return as run
        With script.reel as script
        Output a.mp4
        Say "Two at once."
        Wait for marked
        """)
        #expect(tape.launch == .together)
        #expect(tape.tracks.map(\.name) == ["term", "script"])
        #expect(tape.tracks.map(\.line) == [1, 6])
        #expect(tape.tracks[0].file == nil)
        #expect(tape.tracks[1].file == folder.url.appending(path: "script.reel"))
        let term = tape.tracks[0].tape
        #expect(term.launch == .screen(.terminal))
        #expect(term.terminal.columns == 50)
        // A track's steps keep their lines in the file, so what is said about them is about the file.
        #expect(term.steps.map(\.line) == [3, 5])
        #expect(term.steps.map(\.name) == [nil, "run"])
        #expect(tape.tracks[1].tape.steps.map(\.name) == [nil, "marked"])
        // The unindented steps are the director's; it waits for a track's step, which is not its own.
        #expect(tape.steps.map(\.source) == ["Say \"Two at once.\"", "Wait for marked"])
        #expect(tape.steps.last?.command == .waitFor("marked", end: false))
    }

    @Test func refusals() throws {
        let folder = try Folder()
        let cases: [(String, Int?, String)] = [
            (
                "Screen code as a\n  Code A.swift\nOutput a.mp4\nType \"x\"",
                4,
                "Type acts on a subject: indent it under the track it belongs to"
            ),
            (
                "Screen code as a\n  Code A.swift\n  Go \"nowhere\"\n  Go\nOutput a.mp4",
                4,
                "expected Go line <n>, Go hunk <n> or Go \"<text>\""
            ),
            (
                "Screen code as a\n  Code A.swift\nScreen code as a\n  Code A.swift\nOutput a.mp4",
                3,
                "line 1 is already named a"
            ),
            (
                "Screen code as a\n  Code A.swift as here\nWith script.reel as here\nOutput a.mp4",
                3,
                "line 2 is already named here"
            ),
            (
                "Screen code\nOutput a.mp4\nScreen terminal as t",
                3,
                "line 1 says what this reel records alone; a reel of tracks names each, Screen … as <name>"
            ),
            ("With script.reel\nOutput a.mp4", 1, "expected With <track.reel> as <name>"),
            (
                "With nothing.reel as n\nOutput a.mp4",
                1,
                "no reel at \(folder.url.appending(path: "nothing.reel").path)"
            ),
        ]
        for (text, line, message) in cases {
            #expect(folder.failure(text) == TapeError(line: line, message: message), "\(text)")
        }
    }
}

struct TrackLayoutTests {
    @Test func wideSideBySideTallStacked() {
        let sizes = [CGSize(width: 1600, height: 900), CGSize(width: 1280, height: 720)]
        let wide = TrackLayout.make(
            names: ["a", "b"], sizes: sizes, scales: [2, 2], shape: .aspect(16, 9), padding: 0.06
        )
        #expect(abs(wide.canvas.width / wide.canvas.height - 16.0 / 9) < 0.01)
        let cells = wide.placements(wide.stage).compactMap(\.frame)
        // Left to right, as tall as each other, one after the other.
        #expect(cells[0].maxX < cells[1].minX)
        #expect(abs(cells[0].height - cells[1].height) < 0.5)
        #expect(abs(cells[0].width / cells[0].height - 16.0 / 9) < 0.01)
        let tall = TrackLayout.make(
            names: ["a", "b"], sizes: sizes, scales: [2, 2], shape: .aspect(9, 16), padding: 0.06
        )
        #expect(abs(tall.canvas.width / tall.canvas.height - 9.0 / 16) < 0.01)
        let stacked = tall.placements(tall.stage).compactMap(\.frame)
        // Top to bottom, as wide as each other.
        #expect(stacked[0].maxY < stacked[1].minY)
        #expect(abs(stacked[0].width - stacked[1].width) < 0.5)
    }
}

struct TogetherTests {
    @Test func aDeadlockStopsAtOnce() async throws {
        let channel = try Channel.fresh(
            at: FileManager.default.temporaryDirectory.appending(path: "reel-deadlock-\(UUID().uuidString).jsonl")
        )
        channel.expect(["a-done", "b-done"])
        channel.join("a")
        channel.join("b")
        let started = ContinuousClock.now
        let error = await #expect(throws: ReelError.self) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await channel.wait(for: "b-done", end: false, timeout: .seconds(10), as: "a") }
                group.addTask { try await channel.wait(for: "a-done", end: false, timeout: .seconds(10), as: "b") }
                try await group.next()
                group.cancelAll()
            }
        }
        #expect(error?.description == "no track can go on: a waits for b-done; b waits for a-done")
        #expect(ContinuousClock.now - started < .seconds(2), "caught at once, not after the timeout")
    }

    @Test func aWaitForAnotherProcessIsNoDeadlock() async throws {
        let channel = try Channel.fresh(
            at: FileManager.default.temporaryDirectory.appending(path: "reel-outside-\(UUID().uuidString).jsonl")
        )
        channel.expect(["mine"])
        channel.join("a")
        // `ready` is no track's here: a reel running in a terminal might say it.
        let error = await #expect(throws: ReelError.self) {
            try await channel.wait(for: "ready", end: false, timeout: .milliseconds(150), as: "a")
        }
        #expect(error?.description.hasPrefix("waited 150ms for ready") == true)
    }

    @Test func realInputTakesTurns() async throws {
        let turns = InputTurns()
        let log = Log()
        await withTaskGroup(of: Void.self) { group in
            for name in ["a", "b"] {
                group.addTask {
                    await turns.take()
                    await log.add("\(name) in")
                    try? await Task.sleep(for: .milliseconds(50))
                    await log.add("\(name) out")
                    await turns.give()
                }
            }
        }
        let lines = await log.lines
        // One at a time: each is out before the other is in.
        #expect(lines.count == 4 && lines[0].hasSuffix("in") && lines[1].hasSuffix("out") && lines[1].first == lines[0]
            .first)
    }

    actor Log {
        var lines: [String] = []
        func add(_ line: String) {
            lines.append(line)
        }
    }
}

@Suite(.serialized)
struct TrackRecordingTests {
    @Test func tracksRecordAtOnceAndRenderTogether() async throws {
        let folder = try Folder()
        let script = """
        Screen terminal as term
          Set Columns 40
          Set Rows 5
          Wait for opened
          Type@0ms "echo hi"
          Key return as run
          Wait /hi/
        Screen code as script
          Set Viewport 480x270
          Code A.swift as opened
          Wait for run
          Mark "let x" 1 as marked
        Output wide.mp4
        Output@9:16 tall.mp4
        Wait for marked
        """
        let url = folder.url.appending(path: "together.reel")
        try script.write(to: url, atomically: true, encoding: .utf8)
        let tape = try folder.parse(script)
        let location = TakeLocation(tape: url)
        try await Tracks.record(tape, into: location, log: { _ in })

        let term = try Tracks.location(of: tape.tracks[0], in: location).read()
        let code = try Tracks.location(of: tape.tracks[1], in: location).read()
        let started = try #require(term.startedAt), codeStarted = try #require(code.startedAt)
        // The code waited for the terminal's return: its mark comes after it, on the one clock.
        // Each waited for the other: they were recorded at once, or neither could have finished.
        let run = started + term.events[2].startMs
        let marked = codeStarted + code.events[2].startMs
        #expect(marked >= run, "marked at \(marked), run at \(run)")
        let director = try JSONDecoder().decode(Take.self, from: Data(contentsOf: Tracks.director(in: location)))
        #expect(director.events.count == 1)

        try await Renderer.render(tape: tape, from: location, log: { _ in })
        for (name, aspect) in [("wide.mp4", 16.0 / 9), ("tall.mp4", 9.0 / 16)] {
            let track = try #require(try await AVURLAsset(url: folder.url.appending(path: name))
                .loadTracks(withMediaType: .video).first)
            let size = try await track.load(.naturalSize)
            #expect(abs(size.width / size.height - aspect) < 0.02, "\(name) is \(size)")
        }
    }
}

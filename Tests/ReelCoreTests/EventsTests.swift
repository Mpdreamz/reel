import Foundation
@testable import ReelCore
import Testing

/// Keeps every event it is given, in order.
private final class Recording: EventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [RunEvent] = []

    func emit(_ event: RunEvent) {
        lock.withLock { kept.append(event) }
    }

    var events: [RunEvent] {
        lock.withLock { kept }
    }

    var steps: [(line: Int, index: Int, count: Int, phase: RunEvent.Phase)] {
        events.compactMap { if case let .step(line, _, index, count, phase) = $0.kind {
            (line, index, count, phase)
        } else { nil } }
    }

    var passes: [RunEvent.Pass] {
        events.compactMap { if case let .pass(pass) = $0.kind { pass } else { nil } }
    }
}

struct RunEventCodingTests {
    @Test func everyKindReadsBackAsWritten() throws {
        let kinds: [RunEvent.Kind] = [
            .started(
                reel: "/a/demo.reel",
                command: "run",
                scenes: ["one.reel"],
                profiles: ["github"],
                outputs: ["d.mp4"]
            ),
            .scene(index: 2, count: 3, reel: "two.reel"),
            .step(line: 12, source: "Click \"Play\"", index: 3, count: 14, phase: .start),
            .recording(phase: .start, window: RunEvent.Rect(x: 10, y: 20, width: 640, height: 480), excluded: [42, 7]),
            .recording(phase: .end, window: nil, excluded: []),
            .excluded([99]),
            .pass(RunEvent.Pass(
                name: .encode, profile: "github", output: "d.mp4", detail: "scene 1 of 2", attempt: 2, fraction: 0.5
            )),
            .wrote(path: "/a/d.mp4", summary: "9.4 MB"),
            .note("recording Musicbox, 1280×800"),
            .failed("line 3: no button Play"),
            .ended(ok: false),
        ]
        for kind in kinds {
            let event = RunEvent(at: 1_700_000_000_000, pid: 123, track: "term", kind: kind)
            #expect(RunEvent.lines(event.line) == [event])
        }
    }

    @Test func aLineStillBeingWrittenIsSkipped() {
        let whole = RunEvent(at: 1, pid: 2, kind: .note("whole"))
        var data = whole.line
        data.append(contentsOf: Data(#"{"at":2,"pid":2,"kind":"no"#.utf8))
        #expect(RunEvent.lines(data) == [whole])
    }

    @Test func linesWrittenAtOnceStayWhole() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "reel-events-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = FileSink(url: url)
        let text = String(repeating: "x", count: 2000)
        await withTaskGroup(of: Void.self) { group in
            for writer in 0 ..< 8 {
                group.addTask {
                    for n in 0 ..< 50 {
                        sink.emit(RunEvent(at: n, pid: Int32(writer), kind: .note(text)))
                    }
                }
            }
        }
        let events = try RunEvent.lines(Data(contentsOf: url))
        #expect(events.count == 400)
        #expect(events.allSatisfy { $0.kind == .note(text) })
    }
}

struct ReporterTests {
    @Test func aPassNeverGoesBackAndEndsAtOne() async throws {
        let sink = Recording()
        try await Events.$sink.withValue(sink) {
            try await Events.pass(.encode) {
                try await Task.sleep(for: .milliseconds(120))
                Events.report(0.5)
                try await Task.sleep(for: .milliseconds(120))
                Events.report(0.25)
                try await Task.sleep(for: .milliseconds(120))
                Events.report(0.75)
            }
        }
        #expect(sink.passes.map(\.fraction) == [0, 0.5, 0.75, 1])
    }

    @Test func reportsCloserTogetherThanTheIntervalAreDropped() async throws {
        let sink = Recording()
        try await Events.$sink.withValue(sink) {
            try await Events.pass(.gif) {
                for n in 1 ... 100 {
                    Events.report(Double(n) / 200)
                }
            }
        }
        // The start, at most one more in the same instant, and the end.
        #expect(sink.passes.count <= 3)
        #expect(sink.passes.first?.fraction == 0)
        #expect(sink.passes.last?.fraction == 1)
    }

    @Test func withoutASinkNothingIsSaid() async throws {
        let value = try await Events.pass(.render) { 42 }
        #expect(value == 42)
        #expect(Events.current == nil)
    }
}

struct RecordingEventsTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-events-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "let a = 1\nlet b = 2\nprint(a + b)\n".write(
            to: folder.appending(path: "a.swift"), atomically: true, encoding: .utf8
        )
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static let code = """
    Screen code
    Set Viewport 320x180
    Set FrameRate 30
    Output code.mp4
    Output code.gif
    Code a.swift
    Caption "not recorded"
    Go line 2
    Sleep 300ms
    """

    @Test func aCodeScreenSaysEachStepAndHowFarItsDrawingIs() async throws {
        let url = try write("code.reel", Self.code)
        let tape = try Tape.parse(Self.code, relativeTo: folder)
        let sink = Recording()
        _ = try await Events.$sink.withValue(sink) {
            try await Recorder.record(tape, into: TakeLocation(tape: url), log: { _ in })
        }
        // The caption is drawn at render time: it is not a step that records, and not counted.
        let steps = sink.steps
        #expect(steps.map(\.line) == [6, 6, 8, 8, 9, 9])
        #expect(steps.map(\.phase) == [.start, .end, .start, .end, .start, .end])
        #expect(steps.map(\.index) == [1, 1, 2, 2, 3, 3])
        #expect(steps.allSatisfy { $0.count == 3 })
        let draws = sink.passes.filter { $0.name == .draw }
        #expect(draws.first?.fraction == 0)
        #expect(draws.last?.fraction == 1)
        #expect(zip(draws, draws.dropFirst()).allSatisfy { $0.fraction <= $1.fraction })
        let kinds = sink.events.map(\.kind)
        #expect(kinds.first == .recording(phase: .start, window: nil, excluded: []))
        #expect(kinds.last == .recording(phase: .end, window: nil, excluded: []))
        #expect(sink.events.allSatisfy { $0.pid == ProcessInfo.processInfo.processIdentifier && $0.track == nil })
    }

    @Test func renderSaysEachPassForItsProfileAndOutput() async throws {
        let script = Self.code.replacingOccurrences(
            of: "Output code.gif",
            with: "Output code.gif\nSet Profiles github, web"
        )
        let url = try write("code.reel", script)
        let tape = try Tape.parse(script, relativeTo: folder)
        let location = TakeLocation(tape: url)
        _ = try await Recorder.record(tape, into: location, log: { _ in })
        let sink = Recording()
        try await Events.$sink.withValue(sink) {
            try await Renderer.render(tape: tape, from: location, log: { _ in })
        }
        let passes = sink.passes
        for profile in ["github", "web"] {
            let mine = passes.filter { $0.profile == profile }
            #expect(Set(mine.map(\.name)) == [.render, .encode, .gif])
            #expect(mine.filter { $0.name == .encode }
                .allSatisfy { $0.output == "code-\(profile).mp4" && $0.attempt == 1 })
            #expect(mine.filter { $0.name == .gif }.allSatisfy { $0.output == "code-\(profile).gif" })
        }
        // Each pass runs from 0 to 1 and never back, before the next starts.
        var open: RunEvent.Pass?
        for pass in passes {
            if pass.fraction == 0 {
                #expect(open == nil || open?.fraction == 1)
            } else {
                #expect(open.map { $0.name == pass.name && $0.fraction <= pass.fraction } == true)
            }
            open = pass
        }
        #expect(open?.fraction == 1)
        let written = sink.events.compactMap { if case let .wrote(path, _) = $0.kind {
            URL(fileURLWithPath: path).lastPathComponent
        } else { nil } }
        #expect(written == ["code-github.mp4", "code-github.gif", "code-web.mp4", "code-web.gif"])
    }

    @Test func aReelOfScenesSaysEachScene() async throws {
        _ = try write("one.reel", Self.code)
        _ = try write("two.reel", Self.code)
        let script = "Include one.reel\nInclude two.reel\nOutput all.mp4\n"
        _ = try write("all.reel", script)
        let tape = try Tape.parse(script, relativeTo: folder)
        let sink = Recording()
        try await Events.$sink.withValue(sink) {
            try await Scenes.record(tape, log: { _ in })
        }
        let scenes = sink.events.compactMap { if case let .scene(index, count, reel) = $0.kind {
            "\(index)/\(count) \(reel)"
        } else { nil } }
        #expect(scenes == ["1/2 one.reel", "2/2 two.reel"])
        // Each scene's steps are counted on their own.
        #expect(sink.steps.map(\.index) == [1, 1, 2, 2, 3, 3, 1, 1, 2, 2, 3, 3])
    }
}

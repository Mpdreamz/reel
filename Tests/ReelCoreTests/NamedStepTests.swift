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

struct NamedStepParsingTests {
    @Test func stepsTakeNamesAndWaitForOthers() throws {
        let tape = try Tape.parse("""
        Launch x
        Output a.mp4
        Wait #lanes as ready
        Click #play as play
        Type "hello" as greeting
        Key space
        Wait for go
        Wait for render-done to end
        """, relativeTo: dir)
        #expect(tape.steps.map(\.name) == ["ready", "play", "greeting", nil, nil, nil])
        #expect(tape.steps.map(\.command).suffix(2) == [.waitFor("go", end: false), .waitFor("render-done", end: true)])
        // The name is part of the line as written.
        #expect(tape.steps[0].source == "Wait #lanes as ready")
        // A wait for another reel needs no Accessibility.
        #expect(try !Tape.parse("Launch x\nOutput a.mp4\nWait for go", relativeTo: dir).drivesTheApp)
    }

    @Test(arguments: [
        ("Launch x\nOutput a.mp4\nClick #a as one\nClick #b as one", 4, "line 3 is already named one"),
        (
            "Launch x\nOutput a.mp4\nClick #a as 1st", 3,
            "a step's name is letters, digits, - and _, starting with a letter, not '1st'"
        ),
        (
            "Launch x\nOutput a.mp4 as out", 2,
            "as names a step, for other reels to wait for; Output is not a step, so it cannot be out"
        ),
        (
            "Launch x\nOutput a.mp4\nClick #a as one\nWait for one", 4,
            "one is this reel's own step (line 3); Wait for waits for a step of another reel"
        ),
        ("Launch x\nOutput a.mp4\nWait for", 3, "expected Wait for <name> or Wait for <name> to end"),
        ("Launch x\nOutput a.mp4\nWait for a b", 3, "expected Wait for <name> or Wait for <name> to end"),
    ] as [(String, Int, String)])
    func refusals(text: String, line: Int, message: String) {
        #expect(failure(text) == TapeError(line: line, message: message))
    }
}

struct ChannelTests {
    private func channel() throws -> Channel {
        try Channel
            .fresh(at: FileManager.default.temporaryDirectory
                .appending(path: "reel-channel-\(UUID().uuidString).jsonl"))
    }

    @Test func whatIsSaidIsHeard() async throws {
        let channel = try channel()
        channel.post(reel: "a.reel", line: 3, name: "ready", phase: .start)
        channel.post(reel: "a.reel", line: 3, name: "ready", phase: .end)
        #expect(channel.events.map(\.phase) == [.start, .end])
        #expect(channel.events.map(\.name) == ["ready", "ready"])
        // Said before the wait: it has already happened.
        try await channel.wait(for: "ready", end: true, timeout: .milliseconds(200))
    }

    @Test func aWaitEndsWhenTheStepComes() async throws {
        let channel = try channel()
        let started = ContinuousClock.now
        Task {
            try await Task.sleep(for: .milliseconds(150))
            channel.post(reel: "b.reel", line: 7, name: "go", phase: .start)
        }
        try await channel.wait(for: "go", end: false, timeout: .seconds(5))
        #expect(ContinuousClock.now - started >= .milliseconds(140))
        // Started is not ended.
        let error = await #expect(throws: ReelError.self) {
            try await channel.wait(for: "go", end: true, timeout: .milliseconds(100))
        }
        #expect(error?.description
            == "waited 100ms for go to end on the channel; the last it heard was b.reel line 7 (go) starting")
    }

    @Test func aWaitWithNothingSaidSaysSo() async throws {
        let channel = try channel()
        let error = await #expect(throws: ReelError.self) {
            try await channel.wait(for: "go", end: false, timeout: .milliseconds(60))
        }
        #expect(error?.description == "waited 60ms for go to start on the channel; nothing has been said on it")
    }

    @Test func aReelAloneSkipsItsWaits() async throws {
        var notes: [String] = []
        try await Channel.wait(nil, for: "go", end: false, timeout: .seconds(1), line: 9) { notes.append($0) }
        #expect(notes == ["line 9: skipped Wait for go: no other reel runs with this one (REEL_CHANNEL is not set)"])
    }
}

@Suite(.serialized)
struct ChannelRecordingTests {
    @Test func aTerminalsShellIsOnItsChannel() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "reel-named-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // What a reel run in the shell would say, said by hand.
        let say = #"echo '{"reel":"inner.reel","line":2,"name":"ready","phase":"start","at":1}' >> "$REEL_CHANNEL""#
        let script = """
        Screen terminal
        Set Columns 100
        Set Rows 6
        Output a.mp4
        Type@0ms "\(say.replacingOccurrences(of: "\"", with: "\\\""))"
        Key return as go
        Wait for ready
        """
        let url = folder.appending(path: "outer.reel")
        try script.write(to: url, atomically: true, encoding: .utf8)
        let location = TakeLocation(tape: url)
        let take = try await Recorder.record(Tape.parse(script, relativeTo: folder), into: location, log: { _ in })
        #expect(take.events.count == 3)
        let heard = Channel(url: location.directory.appending(path: "channel.jsonl")).events
        // Its own steps, its named one among them, and what the shell said.
        #expect(heard.contains { $0.reel == "outer.reel" && $0.name == "go" && $0.phase == .end })
        #expect(heard.contains { $0.reel == "inner.reel" && $0.name == "ready" })
    }
}

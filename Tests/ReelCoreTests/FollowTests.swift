import Foundation
@testable import ReelCore
import Testing

@Suite(.serialized)
struct FollowTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-follow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "Screen code\nCode A.swift\nSleep 1s as first\nSleep 1s as second\n"
            .write(to: folder.appending(path: "demo.reel"), atomically: true, encoding: .utf8)
    }

    @Test func parsing() throws {
        let tape = try Tape.parse("Screen code\nOutput a.mp4\nCode demo.reel\nFollow\nFollow off", relativeTo: folder)
        #expect(tape.steps.map(\.command).suffix(2) == [.follow(true), .follow(false)])
        #expect(throws: TapeError(line: 3, message: "Follow is for a code screen: start the reel with Screen code")) {
            try Tape.parse("Screen terminal\nOutput a.mp4\nFollow", relativeTo: folder)
        }
        #expect(throws: TapeError(line: 4, message: "expected Follow or Follow off")) {
            try Tape.parse("Screen code\nOutput a.mp4\nCode demo.reel\nFollow term", relativeTo: folder)
        }
    }

    /// Plays `script`; `started` is when its clock started on the channel's, taken as playing starts, after the
    /// narration is ready, so a slow machine shifts neither clock against the other.
    private func play(
        _ script: String, channel: Channel?, started: inout Int, notes: inout [String], onStart: () -> Void = {}
    ) async throws -> Recorder.Played {
        let tape = try Tape.parse(script, relativeTo: folder)
        let narration = try await Narration.prepare(
            tape, into: folder, voices: tape.voice.synthesizer(for:), log: { _ in }
        )
        var heard: [String] = []
        let startedAt = Channel.now
        started = startedAt
        onStart()
        let played = try await Recorder.playCode(
            tape, narration: narration, reel: "script.reel", channel: channel, startedAt: startedAt,
            log: { heard.append($0) }
        )
        notes = heard
        return played
    }

    @Test func itHighlightsTheLinesOfTheReelItShowsAsTheyRun() async throws {
        let channel = try Channel.fresh(at: folder.appending(path: "channel.jsonl"))
        // demo.reel, running somewhere else: its line 2 before Follow, 3 and 4 after; another reel's line in between.
        channel.post(reel: "demo.reel", line: 2, name: nil, phase: .start)
        Task {
            try await Task.sleep(for: .milliseconds(450))
            channel.post(reel: "demo.reel", line: 3, name: "first", phase: .start)
            channel.post(reel: "other.reel", line: 9, name: nil, phase: .start)
            try await Task.sleep(for: .milliseconds(300))
            channel.post(reel: "demo.reel", line: 4, name: "second", phase: .start)
        }
        var notes: [String] = []
        var started = 0
        let played = try await play("""
        Screen code
        Output a.mp4
        Code demo.reel
        Follow
        Sleep 1s
        Follow off
        """, channel: channel, started: &started, notes: &notes)
        let follows = played.calls.filter { $0.body.contains("follow") }
        #expect(follows.map { $0.arguments["l"] as? Int } == [2, 3, 4, nil])
        // Line 2 had started before the Follow: it shows from the Follow, which ran after the file's 300ms opening (in
        // real time a little later, how much depends on the machine). Lines 3 and 4 show when they started on the
        // channel, never before the Follow. Measured against the channel's own times, so a slow machine can't fail it.
        let at = { (line: Int) in
            try #require(channel.events.first { $0.reel == "demo.reel" && $0.line == line }).at - started
        }
        let (line2, line3, line4) = try (at(2), at(3), at(4))
        #expect(follows[0].ms >= 300, "\(follows[0].ms)")
        #expect(follows[0].ms > line2)
        #expect(follows[1].ms == max(follows[0].ms, line3))
        #expect(follows[2].ms == max(follows[0].ms, line4))
        #expect(follows[2].ms >= follows[1].ms)
        #expect(follows.allSatisfy { $0.arguments["p"] as? Int == 0 })
    }

    @Test func aloneItSaysSo() async throws {
        var notes: [String] = []
        var started = 0
        let played = try await play(
            "Screen code\nOutput a.mp4\nCode demo.reel\nFollow\nSleep 100ms", channel: nil, started: &started,
            notes: &notes
        )
        #expect(!played.calls.contains { $0.body.contains("follow") })
        #expect(notes == ["line 4: skipped Follow: no reel runs with this one (REEL_CHANNEL is not set)"])
    }

    @Test func aWaitForLastsAsLongAsTheWait() async throws {
        let channel = try Channel.fresh(at: folder.appending(path: "channel.jsonl"))
        // Another reel takes its step 800ms after this one starts playing. The code screen's clock is real time on a
        // channel: the wait, begun after the 200ms Sleep, ends when the step is heard, not as far again after.
        // Measured against the time the step was posted on the channel, so a slow machine can't fail it.
        let (playing, started) = AsyncStream.makeStream(of: Void.self)
        Task {
            var waiting = playing.makeAsyncIterator()
            await waiting.next()
            try await Task.sleep(for: .milliseconds(800))
            channel.post(reel: "demo.reel", line: 3, name: "planted", phase: .start)
        }
        var notes: [String] = []
        var startedAt = 0
        let played = try await play(
            "Screen code\nOutput a.mp4\nSleep 200ms\nWait for planted\nSleep 100ms",
            channel: channel, started: &startedAt, notes: &notes, onStart: { started.yield() }
        )
        let wait = try #require(played.events.first { $0.command == "Wait for planted" })
        let planted = try #require(channel.events.first { $0.name == "planted" }).at - startedAt
        #expect(wait.startMs >= 200, "\(wait.startMs)")
        // Heard no earlier than posted, and later only by the channel's polling: far less than the wait again.
        #expect(wait.endMs >= planted, "\(wait.endMs), posted at \(planted)")
        #expect(wait.endMs - planted < (planted - wait.startMs) / 2, "\(wait.endMs), posted at \(planted)")
        #expect(played.end >= wait.endMs + 100, "\(played.end)")
    }

    @Test @MainActor func thePageMarksTheLine() async throws {
        let page = try await ScreenPage(
            "screen.html", size: CGSize(width: 800, height: 400), options: ["fontSize": 16, "peekLines": 8]
        )
        _ = try await page.call(
            "return await reelScreen.open(f, null)",
            ["f": Recorder.screenFile(CodeFile(url: folder.appending(path: "demo.reel"), lines: nil, at: nil))]
        )
        func marked() async throws -> Int {
            for _ in 0 ..< 10 {
                _ = try await page.pump(20)
            }
            return try #require(try await page.call(
                "return document.querySelectorAll('.follow-line').length"
            ) as? Int)
        }
        _ = try await page.call("return reelScreen.follow(3, 0)")
        #expect(try await marked() == 1)
        // One line at a time: the next moves the mark.
        _ = try await page.call("return reelScreen.follow(4, 0)")
        #expect(try await marked() == 1)
        // A line the pane does not show is passed over; off clears it.
        #expect(try await page.call("return reelScreen.follow(99, 0)") == nil)
        _ = try await page.call("return reelScreen.follow(null, 0)")
        #expect(try await marked() == 0)
    }
}

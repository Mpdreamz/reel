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

    private func play(_ script: String, channel: Channel?, notes: inout [String]) async throws -> Recorder.Played {
        let tape = try Tape.parse(script, relativeTo: folder)
        let narration = try await Narration.prepare(
            tape, into: folder, voices: tape.voice.synthesizer(for:), log: { _ in }
        )
        var heard: [String] = []
        let played = try await Recorder.playCode(
            tape, narration: narration, reel: "script.reel", channel: channel, startedAt: Channel.now,
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
        let played = try await play("""
        Screen code
        Output a.mp4
        Code demo.reel
        Follow
        Sleep 1s
        Follow off
        """, channel: channel, notes: &notes)
        let follows = played.calls.filter { $0.body.contains("follow") }
        #expect(follows.map { $0.arguments["l"] as? Int } == [2, 3, 4, nil])
        // Line 2 had started before the Follow: it shows from then (300ms after the file opened, in real time a little
        // later, how much later depends on the machine), and in any case before line 3 started; the rest when they
        // started (450ms in, real time), never before.
        #expect((300 ..< 450).contains(follows[0].ms), "\(follows[0].ms)")
        #expect((450 ..< 800).contains(follows[1].ms), "\(follows[1].ms)")
        #expect(follows[2].ms > follows[1].ms + 200)
        #expect(follows.allSatisfy { $0.arguments["p"] as? Int == 0 })
    }

    @Test func aloneItSaysSo() async throws {
        var notes: [String] = []
        let played = try await play(
            "Screen code\nOutput a.mp4\nCode demo.reel\nFollow\nSleep 100ms", channel: nil, notes: &notes
        )
        #expect(!played.calls.contains { $0.body.contains("follow") })
        #expect(notes == ["line 4: skipped Follow: no reel runs with this one (REEL_CHANNEL is not set)"])
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

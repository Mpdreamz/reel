import Foundation
@testable import ReelCore
import Testing

/// Code screens recorded in two passes: the steps written down with their times, then drawn.
@Suite(.serialized)
struct CodeLogTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-code-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "struct A {}\n".write(to: folder.appending(path: "A.swift"), atomically: true, encoding: .utf8)
    }

    private func record(_ script: String, channel: Channel?) async throws -> Take {
        let url = folder.appending(path: "code.reel")
        try script.write(to: url, atomically: true, encoding: .utf8)
        return try await Recorder.record(
            Tape.parse(script, relativeTo: folder), into: TakeLocation(tape: url), channel: channel, log: { _ in }
        )
    }

    @Test func onAChannelACodeScreenKeepsRealTime() async throws {
        let script = """
        Screen code
        Set Viewport 480x270
        Output a.mp4
        Code A.swift
        Sleep 400ms as pause
        """
        let channel = try Channel.fresh(at: folder.appending(path: "channel.jsonl"))
        let take = try await record(script, channel: channel)
        let pause = channel.events.filter { $0.name == "pause" }
        #expect(pause.map(\.phase) == [.start, .end])
        // What it says on the channel happens when the take says it does: 400ms apart, as the other reels hear it.
        #expect(pause[1].at - pause[0].at >= 395, "\(pause[1].at - pause[0].at) ms")
        // In real time the take shows when things happened, at least as late as planned and each as long.
        let ends = take.events.map(\.endMs)
        #expect(ends[0] >= 300 && ends[1] - ends[0] >= 400, "\(ends)")
        // Alone, as planned to the millisecond, as fast as it can draw.
        let alone = try await record(script, channel: nil)
        #expect(alone.events.map(\.endMs) == [300, 700])
    }

    @Test func aLateStepMovesWhatFollowsInsteadOfShorteningIt() async throws {
        let clock = TakeClock(real: true)
        try await clock.wait(until: 100)
        // Something held the step up: it is 150ms later than the clock thought.
        try await Task.sleep(for: .milliseconds(150))
        let before = ContinuousClock.now
        try await clock.wait(until: clock.now + 200)
        #expect(ContinuousClock.now - before >= .milliseconds(195), "a 200ms step lasts 200ms")
        #expect(clock.now >= 450)
        // Its own clock is never late: it is wherever it is told.
        let own = TakeClock(real: false)
        try await own.wait(until: 100)
        try await own.wait(until: own.now + 200)
        #expect(own.now == 300)
    }

    @Test @MainActor func reelScriptsAreColoured() async throws {
        let url = folder.appending(path: "demo.reel")
        try "# a demo\nClick #play.button as play\nSleep 1.5s\nWait [stop]\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        let page = try await ScreenPage(
            "screen.html", size: CGSize(width: 800, height: 400), options: ["fontSize": 16, "peekLines": 8]
        )
        _ = try await page.call(
            "return await reelScreen.open(f, null)",
            ["f": Recorder.screenFile(CodeFile(url: url, lines: nil, at: nil))]
        )
        for _ in 0 ..< 20 {
            _ = try await page.pump(20)
        }
        #expect(try await page.call("return document.querySelector('.header .lang').textContent") as? String == "reel")
        func colour(_ text: String) async throws -> String? {
            try await page.call("""
            const span = [...document.querySelectorAll('.view-line span[class*="mtk"]')]
              .find((s) => s.textContent.trim() === t);
            return span ? getComputedStyle(span).color : null
            """, ["t": text]) as? String
        }
        #expect(try await colour("Click") == "rgb(242, 176, 76)", "a command: the theme's keyword amber")
        #expect(try await colour("#play.button") == "rgb(134, 182, 242)", "an identifier: blue")
        #expect(try await colour("1.5s") == "rgb(242, 158, 132)", "a duration: a number")
        #expect(try await colour("[stop]") == "rgb(185, 166, 242)", "a marker")
    }
}

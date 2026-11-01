import AVFoundation
import Foundation
@testable import ReelCore
import Testing

struct MorphParsingTests {
    @Test func morphs() throws {
        let tape = try Tape.parse("""
        Screen code
        Output a.mp4
        Morph after.swift
        Morph@ease-out,600ms before.swift lines 2-9 at "func say"
        """, relativeTo: URL(fileURLWithPath: "/tmp/demos"))
        #expect(tape.steps.map(\.command) == [
            .morph(CodeFile(url: URL(fileURLWithPath: "/tmp/demos/after.swift"), lines: nil, at: nil), motion: nil),
            .morph(
                CodeFile(url: URL(fileURLWithPath: "/tmp/demos/before.swift"), lines: 2 ... 9, at: .text("func say")),
                motion: Transition(easing: .easeOut, duration: .milliseconds(600))
            ),
        ])
        #expect(throws: TapeError(
            line: 3,
            message: "'@slide-left' is not a transition; write an easing, a duration or both, such as @ease-out,600ms"
        )) { try Tape.parse(
            "Screen code\nOutput a.mp4\nMorph@slide-left a.swift",
            relativeTo: URL(fileURLWithPath: "/tmp")
        ) }
        #expect(throws: TapeError(line: 3, message: "Morph is for a code screen: start the reel with Screen code")) {
            try Tape.parse("Screen terminal\nOutput a.mp4\nMorph a.swift", relativeTo: URL(fileURLWithPath: "/tmp"))
        }
    }
}

@Suite(.serialized)
struct MorphDrawingTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-morph-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(_ name: String, _ text: String) throws -> [String: Any] {
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return try Recorder.screenFile(CodeFile(url: url, lines: nil, at: nil))
    }

    @Test @MainActor func wordsMoveToTheirNewPlacesAndLinesStayWhole() async throws {
        let page = try await ScreenPage(
            "screen.html", size: CGSize(width: 900, height: 500), options: ["fontSize": 16, "peekLines": 8]
        )
        let before = try file("before.swift", "public var x\npublic func f\n")
        let after = try file("after.swift", "public var y\npublic var x\npublic func f\n")
        _ = try await page.call("return await reelScreen.open(f, null)", ["f": before])
        for _ in 0 ..< 20 {
            _ = try await page.pump(20)
        }
        #expect(try await page.call(
            "return await reelScreen.morph(f, {easing: 'linear', ms: 400})", ["f": after]
        ) == nil)
        let start = try #require(try await page.call(
            "return parseFloat([...document.querySelectorAll('.morph .word')].find((w) => w.textContent === 'x').style.top)"
        ) as? Double)
        _ = try await page.pump(200)
        // Halfway: the real text hidden, the words drawn over it.
        #expect(try await page.call("return document.querySelector('.pane').classList.contains('morphing')") as? Bool
            == true)
        let words = try #require(try await page.call("""
        return [...document.querySelectorAll('.morph .word')].map((w) => [w.textContent, parseFloat(w.style.top),
          parseFloat(w.style.opacity || '1')])
        """) as? [[Any]])
        func tops(_ text: String) -> [Double] {
            words.filter { $0[0] as? String == text }.compactMap { $0[1] as? Double }
        }
        // `public var x` moved down a line as one: halfway, its words are level with each other, between two lines.
        let x = try #require(tops("x").first)
        // It has come part of the way down to its new line.
        #expect(x > start + 4, "x from \(start) to \(x)")
        #expect(tops("var").contains { abs($0 - x) < 0.5 }, "var at \(tops("var")), x at \(x)")
        #expect(tops("public").contains { abs($0 - x) < 0.5 })
        // Drawn as Monaco draws them, without the font's ligatures, so `->` stays `->` and nothing jumps at the end.
        let features = try await page.call(
            "return getComputedStyle(document.querySelector('.morph .word')).fontFeatureSettings"
        ) as? String
        #expect(features?.contains("\"calt\" 0") == true, "\(features ?? "none")")
        // y is new: half faded in at most.
        let y = try #require(words.first { $0[0] as? String == "y" })
        #expect((y[2] as? Double ?? 1) <= 0.01)
        _ = try await page.pump(220)
        #expect(try await page.call("return document.querySelectorAll('.morph').length") as? Int == 0)
        #expect(try await page.call("return document.querySelector('.pane').classList.contains('morphing')") as? Bool
            == false)
        // With nothing shown yet, a morph only opens the file.
        let fresh = try await ScreenPage(
            "screen.html", size: CGSize(width: 900, height: 500), options: ["fontSize": 16, "peekLines": 8]
        )
        #expect(try await fresh.call(
            "return await reelScreen.morph(f, {easing: 'linear', ms: 400})", ["f": after]
        ) == nil)
        #expect(try await fresh.call("return document.querySelectorAll('.morph').length") as? Int == 0)
    }

    @Test func theSameMorphDrawsTheSameTake() async throws {
        _ = try file("before.swift", "struct A {\n    var x = 1\n}\n")
        _ = try file("after.swift", "struct A {\n    var y = 2\n    var x = 1\n}\n")
        let script = """
        Screen code
        Set Viewport 640x360
        Set FrameRate 30
        Output a.mp4
        Code before.swift
        Morph@500ms after.swift
        Morph before.swift
        """
        var takes: [Take] = []
        var frames: [[Data]] = []
        for name in ["one", "two"] {
            let url = folder.appending(path: "\(name).reel")
            try script.write(to: url, atomically: true, encoding: .utf8)
            let location = TakeLocation(tape: url)
            try await takes.append(Recorder.record(
                Tape.parse(script, relativeTo: folder),
                into: location,
                log: { _ in }
            ))
            try await frames.append(movieFrames(AVURLAsset(url: location.movie)))
        }
        #expect(takes[0] == takes[1])
        #expect(takes[0].events.map(\.endMs) == [300, 800, 1700])
        #expect(frames[0].count == frames[1].count && frames[0].count > 20)
        for (index, (a, b)) in zip(frames[0], frames[1]).enumerated() {
            #expect(frameDifference(a, b) < 0.5, "frame \(index) differs by \(frameDifference(a, b))")
        }
    }
}

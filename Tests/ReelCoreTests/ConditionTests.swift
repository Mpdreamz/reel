import Foundation
@testable import ReelCore
import Testing

private let dir = URL(fileURLWithPath: "/tmp/reel-condition-tests")

private func parse(_ text: String) throws -> Tape {
    try Tape.parse(text, relativeTo: dir)
}

private func failure(_ text: String) -> String? {
    do {
        _ = try parse(text)
        return nil
    } catch {
        return "\(error)"
    }
}

private func captions(_ tape: Tape) -> [String?] {
    tape.steps.compactMap { if case let .caption(text, _) = $0.command { text } else { nil } }
}

struct ConditionTests {
    @Test func theFirstConditionThatHoldsChoosesAndTheLastValueIsForNone() throws {
        let tape = try parse("Launch x\nOutput a.mp4\nSet Quality github ? 50 : social|feed ? 70 : 65")
        #expect(tape.encoding.quality == 65)
        for (name, quality) in [("github", 50), ("social", 70), ("feed", 70), ("web", 60)] {
            // web sets its own quality, which a profile's settings apply over the tape's.
            let read = try tape.with(profile: tape.profile(named: name))
            #expect(read.encoding.quality == quality, "\(name)")
        }
        let square = try tape.with(profile: tape.profile(named: "square"))
        #expect(square.encoding.quality == 65)
    }

    @Test func whenTwoConditionsHoldTheFirstChooses() throws {
        let tape = try parse("Launch x\nOutput a.mp4\nSet GifColors github|square ? 32 : square ? 64 : 128")
        #expect(try tape.with(profile: tape.profile(named: "square")).gifColors == 32)
    }

    @Test func captionsDifferByProfileAndTheTakeStaysTheSame() throws {
        let tape = try parse("""
        Launch x
        Output a.mp4
        Click "Play"
        Caption github ? "brew install --cask mpdreamz/tap/reel"
                : social|feed ? "Follow for more"
                : "Recorded with reel"
        Sleep 1s
        Key space
        """)
        #expect(captions(tape) == ["Recorded with reel"])
        let social = try tape.with(profile: tape.profile(named: "social"))
        #expect(captions(social) == ["Follow for more"])
        #expect(try captions(tape.with(profile: tape.profile(named: "github"))) ==
            ["brew install --cask mpdreamz/tap/reel"])
        // What recording does is the same, so one take serves them all; lines after the chain keep their numbers.
        #expect(social.actions == tape.actions)
        #expect(tape.steps.last?.line == 8)
    }

    @Test func aConditionCanTestAnOutputsType() throws {
        let tape = try parse("Launch x\nOutput a.mp4\nOutput a.gif\nCaption gif ? \"Short\" : \"The long version\"")
        #expect(tape.conditionsOnFormat)
        #expect(captions(tape) == ["The long version"])
        let gif = try tape.with(profile: nil, format: .gif)
        #expect(captions(gif) == ["Short"])
        #expect(gif.outputs.map(\.format) == [.gif])
        let mp4 = try tape.with(profile: nil, format: .mp4)
        #expect(captions(mp4) == ["The long version"])
        #expect(mp4.outputs.map(\.format) == [.mp4])
        #expect(try !parse("Launch x\nOutput a.mp4\nSet Quality social ? 70 : 60").conditionsOnFormat)
    }

    @Test func introsAndOutrosToo() throws {
        let tape = try parse("Launch x\nOutput a.mp4\nOutro social ? \"Follow\" : \"Recorded with reel\" \"reel\"")
        #expect(tape.outro?.title == "Recorded with reel")
        #expect(try tape.with(profile: tape.profile(named: "social")).outro?.title == "Follow")
    }

    @Test(arguments: [
        (
            "Set Quality github ? social ? 50 : 60 : 65",
            "line 3: a condition inside a ? value can never matter, since one profile renders at a time; chain them instead: github ? 50 : social ? 70 : 65"
        ),
        (
            "Set Quality github ? 50",
            "line 3: a condition needs a : and a value for when it does not hold; expected <profile> ? <value> : <value>, such as social ? 70 : 60"
        ),
        (
            "Set Quality github ? : 50",
            "line 3: nothing between ? and :; expected <profile> ? <value> : <value>, such as social ? 70 : 60"
        ),
        (
            "Set Quality github ? 50 :",
            "line 3: nothing after the last :; expected <profile> ? <value> : <value>, such as social ? 70 : 60"
        ),
        (
            "Set Quality github social ? 50 : 60",
            "line 3: a condition is a profile's name, or names joined by |, such as social|feed; expected <profile> ? <value> : <value>, such as social ? 70 : 60"
        ),
        ("Set Quality github| ? 50 : 60", "line 3: 'github|' names nothing between its |"),
        ("Set Size social ? 800x600 : 1440x900", "line 3: Size cannot differ by profile: it is fixed when recording"),
        ("Set Profiles social ? github : web", "line 3: Profiles cannot differ by profile: it chooses them"),
        (
            "Say social ? \"Hi\" : \"Hello\"",
            "line 3: a condition (?) works in Set, Caption, Intro and Outro, which render decides; Say happens when recording, the same for every profile"
        ),
        (
            "Set Quality tiktok ? 50 : 60",
            "line 3: there is no profile 'tiktok' to test; there are highest, github, web, social, feed or square, and an Output's type: mp4, mov or gif"
        ),
    ])
    func errors(line: String, message: String) {
        #expect(failure("Launch x\nOutput a.mp4\n\(line)") == message)
    }

    @Test func aChosenValueIsCheckedForTheProfileThatChoosesIt() throws {
        let tape = try parse("Launch x\nOutput a.mp4\nSet Quality social ? lots : 60")
        #expect(throws: TapeError.self) { try tape.with(profile: tape.profile(named: "social")) }
    }

    @Test func aQuestionMarkInQuotesIsText() throws {
        let tape = try parse("Launch x\nOutput a.mp4\nCaption \"Ready ? Go : now\"")
        #expect(captions(tape) == ["Ready ? Go : now"])
    }
}

/// Conditions in presets and profiles, which keep their values as text until applied.
struct PresetConditionTests {
    private func repo() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "reel-cond-\(UUID().uuidString)")
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        return root
    }

    @Test func presetAndProfileValuesChooseToo() throws {
        let root = try repo()
        try """
        Set Quality social ? 70
            : 55
        Set Background "my backdrop.png"
        Profile docs extends web
          Set Background social ? #000000 : "docs backdrop.png"
          Set Quality mp4 ? 45 : 50
        """.write(to: root.appending(path: "house.reelpreset"), atomically: true, encoding: .utf8)
        let url = root.appending(path: "a.reel")
        try "Import house.reelpreset\nLaunch x\nOutput a.mp4\nSet Profiles social, docs"
            .write(to: url, atomically: true, encoding: .utf8)
        let tape = try Tape.load(url)
        #expect(tape.encoding.quality == 55)
        // Quoted, with a space, and no condition: the words as they were.
        #expect(tape.background == .image(root.appending(path: "my backdrop.png")))
        #expect(try tape.with(profile: tape.profile(named: "social")).encoding.quality == 70)
        let docs = try tape.with(profile: tape.profile(named: "docs"))
        #expect(docs.background == .image(root.appending(path: "docs backdrop.png")))
        #expect(docs.encoding.quality == 50)
        #expect(docs.conditionsOnFormat)
        #expect(try tape.with(profile: tape.profile(named: "docs"), format: .mp4).encoding.quality == 45)
    }
}

/// A tape whose values differ by Output type, rendered.
struct ConditionRenderTests {
    let writer = TakeWriterTests()

    @Test func eachTypeIsRenderedFromItsOwnReading() async throws {
        let dir = try writer.temporaryDirectory()
        let location = TakeLocation(tape: dir.appending(path: "demo.reel"))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try await writer.writeTake(to: location.movie, seconds: 1, audio: false)
        try location.write(Take(
            width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 1000,
            events: [Take.Event(line: 5, command: "Sleep 1s", startMs: 0, endMs: 1000)]
        ))
        let tape = try Tape.parse(
            "Launch x\nOutput demo.mp4\nOutput demo.gif\nSet VideoWidth mp4 ? 160 : 200\nSleep 1s", relativeTo: dir
        )
        var lines: [String] = []
        try await Renderer.render(tape: tape, from: location, log: { lines.append($0) })
        #expect(lines.count == 2)
        #expect(lines[0].contains("demo.mp4 (") && lines[0].contains("160x100"))
        #expect(lines[1].contains("demo.gif ("))
    }
}

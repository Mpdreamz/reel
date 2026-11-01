import AppKit
import AVFoundation
import Foundation
@testable import ReelCore
import Testing

extension TrackLayout {
    /// Every track there, as the layout starts.
    var stage: Stage {
        Stage(arrangement: everyTrack, split: nil, spotlight: nil, fullscreen: nil, pip: nil, present: Set(names))
    }

    func stage(_ moves: Move...) -> Stage {
        var stage = stage
        for move in moves {
            stage.apply(move)
        }
        return stage
    }

    func frames(_ moves: Move...) -> [String: CGRect] {
        var stage = stage
        for move in moves {
            stage.apply(move)
        }
        return Dictionary(uniqueKeysWithValues: zip(names, placements(stage)).compactMap { name, placement in
            placement.alpha > 0 ? placement.frame.map { (name, $0) } : nil
        })
    }
}

private func area(_ rect: CGRect?) -> Double {
    rect.map { $0.width * $0.height } ?? 0
}

/// A terminal, a script and an app, laid out on a wide canvas.
private let three = TrackLayout.make(
    names: ["term", "script", "app"],
    sizes: [CGSize(width: 1200, height: 900), CGSize(width: 1200, height: 900), CGSize(width: 1600, height: 1000)],
    scales: [2, 2, 2], shape: .aspect(16, 9), padding: 0.06
)

private func layout(_ text: String) throws -> Layout {
    try Layout.parse(text) { TapeError(line: 1, message: $0) }
}

private func layoutFailure(_ text: String) -> String? {
    do {
        _ = try layout(text)
        return nil
    } catch {
        return (error as? TapeError)?.message
    }
}

struct LayoutParsingTests {
    @Test func cutsGroupsAndShares() throws {
        #expect(try layout("term | app") == .cut(.across, [
            .init(arrangement: .track("term"), share: nil), .init(arrangement: .track("app"), share: nil),
        ]))
        #expect(try layout("(term / script) | app").description == "(term / script) | app")
        #expect(try layout("term/script").description == "term / script")
        #expect(try layout("term 40% | app").description == "term 40% | app")
        #expect(try layout("app").description == "app")
        #expect(try layout("(term / script) | app").names == ["term", "script", "app"])
    }

    @Test func refusals() {
        let cases: [(String, String)] = [
            ("term | app / script", "a layout mixes | and / only in groups: write (a | b) / c or a | (b / c)"),
            ("term 70% | app 40%", "the shares in a cut add up to 110%; they make at most 100%"),
            ("term 70% | app 20%", "the shares in a cut add up to 90%; when every part has one they make 100%"),
            ("(term | app", "a ( in the layout is not closed"),
            ("term |", "the layout ends early; " + Layout.usage),
            ("term 120% | app", "a share is a percentage above 0% and below 100%, such as term 40% | app"),
            ("term 40%", "a share belongs to a part of a cut, such as term 40% | app"),
            ("term, app", "', app' does not belong in a layout; " + Layout.usage),
        ]
        for (text, message) in cases {
            #expect(layoutFailure(text) == message, "\(text)")
        }
    }
}

/// A folder with a script for the tracks to show.
private struct Folder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "reel-directing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "let x = 1\n".write(to: url.appending(path: "A.swift"), atomically: true, encoding: .utf8)
    }

    static let tracks = "Screen terminal as term\n  Type \"ls\"\nScreen code as script\n  Code A.swift\n"

    func parse(_ text: String, profile: String? = nil) throws -> Tape {
        let tape = try Tape.parse(Self.tracks + text, relativeTo: url)
        return try profile.map { try tape.with(profile: tape.profile(named: $0)) } ?? tape
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

struct DirectorMoveParsingTests {
    private func moves(_ tape: Tape) -> [Move] {
        tape.steps.compactMap { if case let .move(move, _) = $0.command { move } else { nil } }
    }

    @Test func movesAndTheLayout() throws {
        let folder = try Folder()
        let tape = try folder.parse("""
        Output a.mp4
        Set Layout script 40% | term
        Say "Watch."
        Spotlight term
        Split 30%
        Fullscreen@smooth,1s script
        Fullscreen off
        Pip term over script top-left
        Pip script
        Pip off
        Layout term / script
        Split off
        Spotlight off
        """)
        #expect(tape.layout?.description == "script 40% | term")
        #expect(try moves(tape) == [
            .spotlight("term"), .split([0.3]), .fullscreen("script"), .fullscreen(nil),
            .pip(Pip(name: "term", over: "script", corner: .topLeft)),
            .pip(Pip(name: "script", over: nil, corner: .bottomRight)), .pip(nil),
            .layout(layout("term / script")), .split(nil), .spotlight(nil),
        ])
        guard case let .move(_, transition) = tape.steps[3].command else { Issue.record("not a move"); return }
        #expect(transition == Transition(easing: .smooth, duration: .seconds(1)))
        // Drawn at render time, so recording skips them.
        #expect(tape.actions.map(\.source) == ["Say \"Watch.\""])
    }

    @Test func aMoveDiffersByProfile() throws {
        let folder = try Folder()
        let text = "Output a.mp4\nSpotlight social ? term : script\n"
        let moved = { (profile: String?) in try moves(folder.parse(text, profile: profile)) }
        #expect(try moved(nil) == [.spotlight("script")])
        #expect(try moved("social") == [.spotlight("term")])
        // The layout too, by a condition or in a profile.
        let chosen = "Output a.mp4\nSet Layout social ? term / script : script | term\n"
        #expect(try folder.parse(chosen).layout?.description == "script | term")
        #expect(try folder.parse(chosen, profile: "social").layout?.description == "term / script")
        let profiled = "Output a.mp4\nProfile stacked\n  Set Layout term / script\n"
        #expect(try folder.parse(profiled).layout == nil)
        #expect(try folder.parse(profiled, profile: "stacked").layout?.description == "term / script")
    }

    @Test func refusals() throws {
        let folder = try Folder()
        let cases: [(String, Int?, String)] = [
            ("Output a.mp4\nSpotlight app", 6, "there is no track app; the tracks are term, script"),
            ("Output a.mp4\nLayout term | term", 6, "term is in the layout twice"),
            ("Output a.mp4\nSet Layout term | app", nil, "line 6: there is no track app; the tracks are term, script"),
            ("Output a.mp4\nPip term over term", 6, "a picture-in-picture is over another track, not itself"),
            (
                "Output a.mp4\nPip term middle", 6,
                "'middle' is not a corner; expected top-left, top-right, bottom-left, bottom-right"
            ),
            ("Output a.mp4\nSplit 60% 50%", 6, "the shares add up to 110%; they make at most 100%"),
            ("Output a.mp4\nSplit half", 6, "expected Split <share>% …, such as Split 40%, or Split off"),
            ("Output a.mp4\nFullscreen", 6, "expected Fullscreen <track> or Fullscreen off"),
        ]
        for (text, line, message) in cases {
            #expect(folder.failure(text) == TapeError(line: line, message: message), "\(text)")
        }
    }

    @Test func movesAreTheDirectorsAlone() throws {
        let folder = try Folder()
        for (text, message) in [
            (
                "Screen code\nOutput a.mp4\nSpotlight term",
                "Spotlight directs the tracks of a reel that records several at once (… as <name>)"
            ),
            (
                "Screen code\nOutput a.mp4\nSet Layout a | b",
                "Set Layout arranges the tracks of a reel that records several at once (… as <name>)"
            ),
            ("Screen terminal\nOutput a.mp4\nSplit 40%", "Split is for a code screen: start the reel with Screen code"),
        ] {
            do {
                _ = try Tape.parse(text, relativeTo: folder.url)
                Issue.record("\(text) parsed")
            } catch let error as TapeError {
                #expect(error.message == message, "\(text)")
            }
        }
    }
}

struct DirectingLayoutTests {
    @Test func groupsCutWithinCuts() throws {
        var stage = three.stage
        stage.arrangement = try layout("(term / script) | app")
        let frames = Dictionary(uniqueKeysWithValues: zip(three.names, three.placements(stage).map(\.frame!)))
        let term = try #require(frames["term"]), script = try #require(frames["script"])
        let app = try #require(frames["app"])
        #expect(term.maxY < script.minY)
        #expect(term.maxX < app.minX && script.maxX < app.minX)
        // Inside the room, and none overlapping.
        for frame in frames.values {
            #expect(three.room.insetBy(dx: -1, dy: -1).contains(frame))
        }
        #expect(!term.intersects(app) && !script.intersects(app))
    }

    @Test func aTallCanvasStacksWhatIsSideBySide() throws {
        let tall = TrackLayout.make(
            names: three.names, sizes: three.sizes, scales: three.scales, shape: .aspect(9, 16), padding: 0.06
        )
        var stage = tall.stage
        stage.arrangement = try layout("(term / script) | app")
        let frames = tall.placements(stage).map(\.frame!)
        #expect(frames[0].maxY < frames[1].minY && frames[1].maxY < frames[2].minY)
    }

    @Test func aSpotlightGrowsItsTrackAndShrinksTheOthers() {
        let before = three.frames()
        let after = three.frames(.spotlight("term"))
        #expect(area(after["term"]) > area(before["term"]) * 1.3)
        #expect(area(after["app"]) < area(before["app"]))
        #expect(area(after["term"]) > area(after["app"]) * 2)
        // Off gives back what was.
        #expect(three.frames(.spotlight("term"), .spotlight(nil)) == before)
    }

    @Test func aSplitSharesTheTopCut() {
        let frames = three.frames(.split([0.5]))
        // Half the room's width, less the gaps, is the terminal's cell; it fits it.
        let gaps = TrackLayout.gap * three.room.height * 2
        let cell = (three.room.width - gaps) * 0.5
        #expect(abs((frames["term"]?.width ?? 0) - cell) < 1)
        #expect(three.frames(.split([0.5]), .split(nil)) == three.frames())
    }

    @Test func fullscreenIsOneTrackAsLargeAsTheRoomHoldsIt() {
        let frames = three.frames(.fullscreen("app"))
        #expect(Array(frames.keys) == ["app"])
        let app = frames["app"]!
        #expect(abs(app.width - three.room.width) < 1 || abs(app.height - three.room.height) < 1)
        #expect(three.placements(three.stage(.fullscreen("app")))[2].z > 0)
        #expect(three.frames(.fullscreen("app"), .fullscreen(nil)) == three.frames())
    }

    @Test func aPictureInPictureSitsInItsCornerOverTheRest() throws {
        let frames = three.frames(.pip(Pip(name: "term", over: nil, corner: .bottomRight)))
        let term = try #require(frames["term"]), script = try #require(frames["script"])
        let app = try #require(frames["app"])
        let under = script.union(app)
        // Small, inside what it is over, at its bottom right, and on top.
        #expect(under.contains(term))
        #expect(term.maxX > under.midX && term.maxY > under.midY)
        #expect(term.width <= under.width * TrackLayout.pipShare + 1)
        let placements = three.placements(three.stage(.pip(Pip(name: "term", over: nil, corner: .bottomRight))))
        #expect(placements[0].z > placements[1].z)

        // Over one track: that one fills, the rest fade.
        let over = three.frames(.pip(Pip(name: "term", over: "app", corner: .topLeft)))
        #expect(Set(over.keys) == ["term", "app"])
        #expect(over["term"]!.minX < over["app"]!.midX && over["term"]!.minY < over["app"]!.midY)
    }

    @Test func aLayoutEndsAFullscreenAndKeepsOnlyItsTracks() throws {
        let frames = try three.frames(.fullscreen("app"), .layout(layout("script | term")))
        #expect(Set(frames.keys) == ["script", "term"])
        #expect(frames["script"]!.maxX < frames["term"]!.minX)
    }
}

struct DirectionTests {
    @Test func aMoveEasesFromWhereEverythingWas() {
        let direction = Direction.make(
            layout: three, start: nil, starts: [0, 0, 0],
            moves: [(1, .fullscreen("app"), Transition(easing: .linear, duration: .seconds(1)))]
        )
        let first = three.placements(three.stage)
        let last = three.placements(three.stage(.fullscreen("app")))
        #expect(direction.placements(at: 0.5) == first)
        #expect(direction.placements(at: 2) == last)
        let half = direction.placements(at: 1.5)
        #expect(abs(half[2].frame!.width - (first[2].frame!.width + last[2].frame!.width) / 2) < 0.01)
        #expect(abs(half[0].alpha - 0.5) < 0.01)
    }

    @Test func aTrackThatStartsLateGrowsInWhenItStarts() {
        let direction = Direction.make(layout: three, start: nil, starts: [0, 0.2, 3], moves: [])
        let early = direction.placements(at: 1)
        // The app is not there yet: the two that are share the room.
        #expect(early[2].alpha == 0)
        #expect(early[0].alpha == 1 && early[1].alpha == 1)
        let growing = direction.placements(at: 3.2)
        #expect(growing[2].alpha > 0 && growing[2].alpha < 1)
        let grown = direction.placements(at: 5)
        #expect(grown == three.placements(three.stage))
        #expect(area(early[0].frame) > area(grown[0].frame))
    }

    @Test func aMoveMidwayStartsFromWhereItHadGot() {
        let direction = Direction.make(
            layout: three, start: nil, starts: [0, 0, 0],
            moves: [
                (0, .fullscreen("app"), Transition(easing: .linear, duration: .seconds(2))),
                (1, .fullscreen(nil), Transition(easing: .linear, duration: .seconds(2))),
            ]
        )
        let midway = direction.placements(at: 0.999)
        let after = direction.placements(at: 1.001)
        // No jump: the second move starts where the first had got to.
        #expect(abs(midway[2].frame!.width - after[2].frame!.width) < 2)
    }
}

/// Two still clips composed with the director's moves: what is on the canvas at a moment.
@Suite(.serialized)
struct DirectedCompositionTests {
    @Test func theCompositorDrawsWhereTheDirectorSays() async throws {
        let folder = try Folder()
        let red = folder.url.appending(path: "red.mov"), blue = folder.url.appending(path: "blue.mov")
        try await StillClip.write(.color(1, 0, 0), size: CGSize(width: 320, height: 180), seconds: 3, to: red)
        try await StillClip.write(.color(0, 0, 1), size: CGSize(width: 320, height: 180), seconds: 3, to: blue)
        let layout = TrackLayout.make(
            names: ["red", "blue"], sizes: [CGSize(width: 320, height: 180), CGSize(width: 320, height: 180)],
            scales: [1, 1], shape: .aspect(16, 9), padding: 0.06
        )
        let direction = Direction.make(
            layout: layout, start: nil, starts: [0, 0],
            moves: [(1, .fullscreen("blue"), Transition(easing: .snap, duration: .zero))]
        )
        let out = folder.url.appending(path: "out.mov")
        _ = try await Renderer.compose(
            [(red, 0), (blue, 0)], direction: direction, background: .color(0, 0, 0), frameRate: 30, atLeast: 0,
            to: out
        )
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: out))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        func colour(at seconds: Double, x: Double) async throws -> (r: Int, b: Int) {
            let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            let rep = NSBitmapImageRep(cgImage: image)
            let colour = rep.colorAt(x: Int(Double(rep.pixelsWide) * x), y: rep.pixelsHigh / 2)!
                .usingColorSpace(.sRGB)!
            return (Int(colour.redComponent * 255), Int(colour.blueComponent * 255))
        }
        // Side by side, red on the left; then blue alone, filling the middle and the left.
        let left = try await colour(at: 0.5, x: 0.25), right = try await colour(at: 0.5, x: 0.75)
        #expect(left.r > 200 && left.b < 50, "\(left)")
        #expect(right.b > 200 && right.r < 50, "\(right)")
        let after = try await colour(at: 2, x: 0.25)
        #expect(after.b > 200 && after.r < 50, "\(after)")
    }
}

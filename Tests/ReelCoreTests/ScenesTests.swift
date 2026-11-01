import AVFoundation
import Foundation
@testable import ReelCore
import Testing

/// A folder with two scenes in it, `a.reel` and `b.reel` (code screens, which record anywhere), and whatever else a
/// test writes.
private struct Folder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "reel-scenes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "struct A {\n    let x = 1\n}\n".write(
            to: url.appending(path: "A.swift"),
            atomically: true,
            encoding: .utf8
        )
        for (name, viewport) in [("a", "640x360"), ("b", "480x480")] {
            try write("\(name).reel", """
            Screen code
            Set Viewport \(viewport)
            Set FrameRate 30
            Output \(name).mp4
            Code A.swift
            Sleep 1s
            """)
        }
    }

    @discardableResult
    func write(_ name: String, _ text: String) throws -> URL {
        let file = url.appending(path: name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
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

struct SceneParsingTests {
    @Test func aReelOfScenes() throws {
        let folder = try Folder()
        try folder.write("look.reelpreset", "Set Voice system\nSet Background #102030\n")
        let tape = try folder.parse("""
        Import look.reelpreset
        Include a.reel
        Include@slide-left,ease-out,800ms b.reel
        Include a.reel
        Output tour.mp4
        Outro "Done"
        """)
        #expect(tape.launch == .sequence)
        #expect(tape.scenes == [
            Scene(url: folder.url.appending(path: "a.reel"), transition: nil),
            Scene(
                url: folder.url.appending(path: "b.reel"),
                transition: SectionTransition(kind: .slideLeft, easing: .easeOut, duration: .milliseconds(800))
            ),
            Scene(url: folder.url.appending(path: "a.reel"), transition: .standard),
        ])
        #expect(tape.steps.isEmpty)
        // A preset's recording settings are for the scenes that import it too; a sequence passes them by.
        let backdrop: Background = .color(16.0 / 255, 32.0 / 255, 48.0 / 255)
        #expect(tape.background == backdrop)
        #expect(try Scenes.load(tape).map(\.tape.launch) == [.screen(.code), .screen(.code), .screen(.code)])
    }

    @Test func refusals() throws {
        let folder = try Folder()
        try folder.write("notes.txt", "")
        let kinds = TransitionKind.allCases.map(\.rawValue).joined(separator: ", ")
        let spin = "'@spin' is not a transition; write a kind (\(kinds)), an easing and a duration, such as "
            + "@slide-left,ease-out,800ms"
        let cases: [(String, Int, String)] = [
            (
                "Include@crossfade a.reel",
                1,
                "the first scene has nothing before it to move from; give the transition on the next Include"
            ),
            ("Include notes.txt", 1, "Include takes a .reel, not notes.txt"),
            ("Include c.reel", 1, "no reel at \(folder.url.appending(path: "c.reel").path)"),
            ("Include a.reel\nInclude@spin b.reel", 2, spin),
            ("Launch x\nInclude a.reel", 2, "Include joins other reels; this reel Launches an app (line 1)"),
            ("Include a.reel\nLaunch x", 2, "this reel joins other reels (line 1); Launch the app in one of them"),
            ("Include a.reel\nOpen https://a.dev", 2, "Open goes to a web page; this reel joins other reels"),
            (
                "Include a.reel\nSet Voice system",
                2,
                "Set Voice is fixed when a scene is recorded: set it in the scene's reel"
            ),
            (
                "Include a.reel\nOutput t.mp4\nSleep 1s",
                3,
                "a reel of scenes has no steps of its own: they belong in its scenes' reels"
            ),
        ]
        for (text, line, message) in cases {
            #expect(folder.failure(text) == TapeError(line: line, message: message), "\(text)")
        }
    }

    @Test func aSceneRendersForTheSequencesProfileWhenItKnowsIt() throws {
        let folder = try Folder()
        try folder.write("c.reel", """
        Screen code
        Output c.mp4
        Profile docs "our docs"
          Set Quality 41
        Code A.swift
        """)
        let tour = try folder.parse("""
        Include c.reel
        Output t.mp4
        Profile docs "our docs"
          Set Quality 70
        Profile slides "a talk"
          Set Quality 80
        """)
        let scene = try #require(try Scenes.load(tour).first?.tape)
        // Its own docs, not the sequence's; a built-in it knows as well; one it does not know, as written.
        #expect(try Scenes.tape(scene, for: tour.profile(named: "docs")).encoding.quality == 41)
        #expect(try Scenes.tape(scene, for: tour.profile(named: "web")).encoding.quality == 60)
        #expect(try Scenes.tape(scene, for: tour.profile(named: "slides")).encoding.quality == 65)
        #expect(try Scenes.tape(scene, for: nil).encoding.quality == 65)
    }

    @Test func aReelOfTracksIsAScene() throws {
        let folder = try Folder()
        try folder.write("both.reel", """
        Screen code as left
          Code A.swift
        Screen code as right
          Code A.swift
        Output both.mp4
        """)
        let scenes = try Scenes.load(folder.parse("Include a.reel\nInclude both.reel\nOutput t.mp4"))
        #expect(scenes.map(\.tape.launch) == [.screen(.code), .together])
        #expect(scenes.map(\.tape.isTracks) == [false, true])
        #expect(scenes[1].tape.tracks.map(\.name) == ["left", "right"])
    }

    @Test func scenesAreJoinedNoLargerThanTheOutputsKeep() {
        let canvas = CGSize(width: 2528, height: 1422)
        let mp4 = Output(url: URL(filePath: "/t.mp4"), format: .mp4)
        let gif = Output(url: URL(filePath: "/t.gif"), format: .gif)
        var narrow = Encoding.standard
        narrow.width = 1920
        func size(_ outputs: [Output], _ encoding: Encoding, gif width: Int = 720) -> CGSize {
            Scenes.workingSize(of: canvas, for: outputs, encoding: encoding, gifWidth: width)
        }
        // As wide as the widest Output, at the size the movie would have been scaled to from the full canvas.
        #expect(size([mp4, gif], narrow) == CGSize(width: 1920, height: 1080))
        #expect(size([mp4, gif], narrow) == narrow.size(for: canvas))
        #expect(size([gif], .standard) == CGSize(width: 720, height: 404))
        #expect(size([mp4, gif], narrow, gif: 2200) == CGSize(width: 2200, height: 1238))
        // A movie at its full size, or Outputs wider than the canvas: the canvas, never larger.
        #expect(size([mp4, gif], .standard) == canvas)
        #expect(size([gif], .standard, gif: 4000) == canvas)
        narrow.width = 8000
        #expect(size([mp4], narrow) == canvas)
    }

    @Test func aSceneJoinsNoScenesOfItsOwn() throws {
        let folder = try Folder()
        try folder.write("inner.reel", "Include a.reel\nOutput i.mp4")
        let tape = try folder.parse("Include inner.reel\nOutput t.mp4")
        #expect(throws: TapeError(
            message: "inner.reel joins scenes itself; a scene cannot join scenes"
        )) { try Scenes.load(tape) }
        try folder.write("broken.reel", "Screen code\nOutput b.mp4\nGo")
        #expect(throws: TapeError(
            message: "broken.reel line 3: expected Go line <n>, Go hunk <n> or Go \"<text>\""
        )) { try Scenes.load(folder.parse("Include broken.reel\nOutput t.mp4")) }
    }
}

/// Records and renders sequences of code screens for real: no permission needed.
@Suite(.serialized)
struct SceneRenderingTests {
    private func render(_ folder: Folder, _ name: String, _ text: String) async throws -> Tape {
        let url = try folder.write(name, text)
        let tape = try Tape.load(url)
        try await Scenes.record(tape, log: { _ in })
        try await Renderer.render(tape: tape, from: TakeLocation(tape: url), log: { _ in })
        return tape
    }

    private func length(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    private func size(_ url: URL) async throws -> CGSize {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        return try await track.load(.naturalSize)
    }

    @Test func scenesPlayOneAfterTheOtherOnOneCanvas() async throws {
        let folder = try Folder()
        _ = try await render(folder, "cut.reel", """
        Include a.reel
        Include@cut b.reel
        Output cut.mp4
        Output@1:1 square.mp4
        """)
        let a = try TakeLocation(tape: folder.url.appending(path: "a.reel")).read()
        let b = try TakeLocation(tape: folder.url.appending(path: "b.reel")).read()
        let both = Double(a.durationMs + b.durationMs) / 1000
        // A cut joins them end to end.
        #expect(try await abs(length(folder.url.appending(path: "cut.mp4")) - both) < 0.1)
        // 16:9 unless the Output says otherwise, every scene on the same canvas.
        let wide = try await size(folder.url.appending(path: "cut.mp4"))
        #expect(abs(wide.width / wide.height - 16 / 9) < 0.01)
        let square = try await size(folder.url.appending(path: "square.mp4"))
        #expect(square.width == square.height)

        // A crossfade overlaps them for its length; an outro follows.
        _ = try await render(folder, "fade.reel", """
        Include a.reel
        Include@crossfade,500ms b.reel
        Output fade.mp4
        Outro "Done" 2s
        """)
        #expect(try await abs(length(folder.url.appending(path: "fade.mp4")) - (both - 0.5 + 2 - 0.6)) < 0.1)
    }

    @Test func aReelOfTracksIsAScene() async throws {
        let folder = try Folder()
        try folder.write("both.reel", """
        Screen code as left
          Set Viewport 480x270
          Set FrameRate 30
          Code A.swift as opened
          Sleep 1s
        Screen code as right
          Set Viewport 480x270
          Set FrameRate 30
          Wait for opened
          Code A.swift
          Mark "let x" 1
          Sleep 500ms
        Output both.mp4
        Spotlight right
        Wait for opened
        """)
        // A scene with no take yet: the director's is what it looks for.
        let alone = try folder.write("alone.reel", "Include both.reel\nOutput alone.mp4")
        let error = await #expect(throws: ReelError.self) {
            try await Renderer.render(tape: Tape.load(alone), from: TakeLocation(tape: alone), log: { _ in })
        }
        #expect(error?.description.hasPrefix("scene 1, both.reel, has no take yet") == true)

        _ = try await render(folder, "tour.reel", """
        Include a.reel
        Include@cut both.reel
        Output tour.mp4
        Output@1:1 square.mp4
        """)
        // Recorded as it records on its own: each track and the director.
        let both = TakeLocation(tape: folder.url.appending(path: "both.reel"))
        let director = try JSONDecoder().decode(Take.self, from: Data(contentsOf: Tracks.director(in: both)))
        let left = both.directory.appending(path: "tracks/left")
        #expect(FileManager.default.fileExists(atPath: TakeLocation(directory: left).timeline.path))
        // Joined end to end after the code scene, drawn together for as long as the director runs.
        let a = try TakeLocation(tape: folder.url.appending(path: "a.reel")).read()
        let wide = try await size(folder.url.appending(path: "tour.mp4"))
        let canvas = TakeLocation(directory: both.directory
            .appending(path: "cuts/\(Int(wide.width))x\(Int(wide.height))"))
        let together = try canvas.read()
        #expect(together.durationMs >= director.durationMs)
        let expected = Double(a.durationMs + together.durationMs) / 1000
        #expect(try await abs(length(folder.url.appending(path: "tour.mp4")) - expected) < 0.15)
        #expect(abs(wide.width / wide.height - 16 / 9) < 0.01)
        let square = try await size(folder.url.appending(path: "square.mp4"))
        #expect(square.width == square.height)
    }

    /// The colour at `x`, `y` (shares of the width and height) of the movie's frame at `seconds`, 0 to 255.
    private func colour(_ url: URL, at seconds: Double, x: Double, y: Double) async throws -> [Int] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // The one pixel wanted lands on the context's only one; Core Graphics' y runs up.
        let (width, height) = (Double(image.width), Double(image.height))
        context.draw(image, in: CGRect(x: -x * width, y: -(1 - y) * height, width: width, height: height))
        return pixel.prefix(3).map(Int.init)
    }

    @Test func joiningKeepsTheScenesColours() async throws {
        let folder = try Folder()
        let sting = URL(filePath: #filePath).deletingLastPathComponent().appending(
            path: "../../design/motion/intro-reel-2s-16x9.mp4"
        ).standardized
        _ = try await render(folder, "colours.reel", """
        Include a.reel
        Include@cut b.reel
        Include@cut a.reel
        Output colours.mp4
        Intro 1s
        Set IntroBackground \(sting.path)
        """)
        // The editor's background, below the code, in the take and in the first scene of the joined movie: three
        // passes (two joins, the intro) that each shifted it a little when Core Animation drew them.
        let take = try await colour(
            TakeLocation(tape: folder.url.appending(path: "a.reel")).movie, at: 0.5, x: 0.5, y: 0.8
        )
        let joined = try await colour(folder.url.appending(path: "colours.mp4"), at: 1.5, x: 0.5, y: 0.7)
        #expect(zip(take, joined).allSatisfy { abs($0 - $1) <= 6 }, "the take's \(take), joined \(joined)")
    }

    @Test func aSceneWithoutATakeSaysHowToGetOne() async throws {
        let folder = try Folder()
        let url = try folder.write("tour.reel", "Include a.reel\nOutput t.mp4")
        let error = await #expect(throws: ReelError.self) {
            try await Renderer.render(tape: Tape.load(url), from: TakeLocation(tape: url), log: { _ in })
        }
        #expect(error?.description
            == "scene 1, a.reel, has no take yet: record it (reel record a.reel), or record every scene with reel run")
    }
}

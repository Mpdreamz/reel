import AVFoundation
import Foundation
@testable import ReelCore
import Testing

private let dir = URL(fileURLWithPath: "/tmp/demos", isDirectory: true)

private func parse(_ text: String) throws -> Tape {
    try Tape.parse(text, relativeTo: dir)
}

private func failure(_ text: String) -> TapeError? {
    do {
        _ = try parse(text)
        return nil
    } catch {
        return error as? TapeError
    }
}

struct ScreenParsingTests {
    @Test func aCodeScreen() throws {
        let tape = try parse("""
        Screen code
        Output code.mp4
        Set Viewport 1280x720
        Set FontSize 20
        Code Sources/Player.swift lines 10-40 at "func play"
        Code Player.java at line 12
        Go line 30
        Go "return"
        Focus lines 20-24
        Focus off
        Mark "speed" 1
        Mark "rate"
        Mark off
        Callout "speed" "how fast it plays"
        Callout off
        Type "x"
        Key shift+left 3
        Key return
        Say "and that is play"
        Zoom @200,100
        """)
        #expect(tape.launch == .screen(.code))
        #expect(tape.launch.isScreen && !tape.launch.isWeb)
        #expect(!tape.drivesTheApp, "a code screen needs no Accessibility")
        #expect(tape.web.viewport == CGSize(width: 1280, height: 720))
        #expect(tape.fontSize == 20)
        #expect(Array(tape.steps.map(\.command).prefix(14)) == [
            .code(CodeFile(
                url: URL(fileURLWithPath: "/tmp/demos/Sources/Player.swift"), lines: 10 ... 40, at: .text("func play")
            ), transition: nil),
            .code(
                CodeFile(url: URL(fileURLWithPath: "/tmp/demos/Player.java"), lines: nil, at: .line(12)),
                transition: nil
            ),
            .go(.line(30)),
            .go(.text("return")),
            .focus(20 ... 24),
            .focus(nil),
            .mark("speed", number: 1),
            .mark("rate", number: nil),
            .mark(nil, number: nil),
            .callout("speed", label: "how fast it plays"),
            .callout(nil, label: nil),
            .type("x", pause: nil),
            .key(KeyCombo("shift+left")!, count: 3),
            .key(KeyCombo("return")!, count: 1),
        ])
        // What a code screen draws is recorded with it, so a take is checked against the steps that make it.
        #expect(tape.actions.count == tape.steps.count - 1, "all but the point zoom")
        #expect(try parse("Screen code\nOutput a.mp4").fontSize == Tape.defaultFontSize)
    }

    @Test(arguments: [
        ("Screen editor\nOutput a.mp4", 1, "expected Screen code or Screen terminal"),
        (
            "Screen code\nOutput a.mp4\nScreen code",
            3,
            "line 1 already says what this reel records; a reel records one thing"
        ),
        ("Screen code\nOutput a.mp4\nLaunch x", 3, "this reel is a code screen (line 1), so there is no app to Launch"),
        ("Screen code\nOutput a.mp4\nOpen https://a.dev", 3, "Open goes to a web page; this reel is a code screen"),
        ("Launch x\nOutput a.mp4\nCode a.swift", 3, "Code is for a code screen: start the reel with Screen code"),
        (
            "Open https://a.dev\nOutput a.mp4\nMark \"x\"",
            3,
            "Mark is for a code or terminal screen: start the reel with Screen code or Screen terminal"
        ),
        (
            "Launch x\nSet FontSize 20",
            2,
            "Set FontSize is for a code or terminal screen (Screen code, Screen terminal)"
        ),
        ("Screen code\nSet FontSize 7", 2, "FontSize must be a whole number of points from 8 to 72, not '7'"),
        ("Screen code\nSet Size 800x600", 2, "Set Size is an app's window; a code screen's size is Set Viewport"),
        ("Screen code\nSet Browser chromium", 2, "Set Browser is for web pages (Open); this reel is a code screen"),
        (
            "Screen code\nOutput a.mp4\nCode \"a.swift\"", 3,
            "expected Code[@<transition>] <file> [lines <a>-<b>] [at line <n> | at \"<text>\"]"
        ),
        (
            "Screen code\nOutput a.mp4\nCode a.swift lines 9-3", 3,
            "expected Code[@<transition>] <file> [lines <a>-<b>] [at line <n> | at \"<text>\"]"
        ),
        (
            "Screen code\nOutput a.mp4\nCode a.swift at func", 3,
            "a place in the code is line <n>, hunk <n> or some text to find, in quotes"
        ),
        (
            "Screen code\nOutput a.mp4\nGo line",
            3,
            "a place in the code is line <n>, hunk <n> or some text to find, in quotes"
        ),
        ("Screen code\nOutput a.mp4\nGo \"a\" \"b\"", 3, "expected Go line <n>, Go hunk <n> or Go \"<text>\""),
        ("Screen code\nOutput a.mp4\nFocus 3-4", 3, "expected Focus lines <a>-<b> or Focus off"),
        ("Screen code\nOutput a.mp4\nMark speed", 3, "expected Mark \"<text>\" [number] or Mark off"),
        ("Screen code\nOutput a.mp4\nMark \"speed\" 100", 3, "a mark's number is 1 to 99, not '100'"),
        ("Screen code\nOutput a.mp4\nCallout \"speed\"", 3, "expected Callout \"<text>\" \"<label>\" or Callout off"),
        (
            "Screen code\nOutput a.mp4\nClick \"Play\"", 3,
            "a code screen has no app or page to drive; it takes Code, Go, Type, Key and the rest"
        ),
        (
            "Screen code\nOutput a.mp4\nScroll down 3", 3,
            "a code screen has no app or page to drive; it takes Code, Go, Type, Key and the rest"
        ),
        (
            "Screen code\nOutput a.mp4\nWait #play",
            3,
            "a code screen has nothing to wait for; Wait [marker] waits for narration"
        ),
        (
            "Screen code\nOutput a.mp4\nZoom \"Play\"",
            3,
            "a code screen zooms on a point (Zoom @x,y) or the cursor, not an element"
        ),
        (
            "Screen code\nOutput a.mp4\nKey cmd+s", 3,
            "a code screen's editor takes the keys backspace, delete, down, end, enter, esc, escape, forwarddelete, "
                + "home, left, pagedown, pageup, return, right, space, tab, up, with shift to select, not cmd+s"
        ),
    ] as [(String, Int, String)])
    func refusals(text: String, line: Int, message: String) {
        #expect(failure(text) == TapeError(line: line, message: message))
    }

    @Test func aFileIsShownAsTheGitRootNamesIt() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "reel-screen-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Sources/Player")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        let url = folder.appending(path: "Player.swift")
        try "one\ntwo\nthree\nfour\n".write(to: url, atomically: true, encoding: .utf8)

        let whole = try Recorder.screenFile(CodeFile(url: url, lines: nil, at: nil))
        #expect(whole["name"] as? String == "Player.swift")
        #expect(whole["directory"] as? String == "Sources/Player")
        #expect(whole["text"] as? String == "one\ntwo\nthree\nfour")
        #expect(whole["firstLine"] as? Int == 1)

        let part = try Recorder.screenFile(CodeFile(url: url, lines: 2 ... 3, at: .text("three")))
        #expect(part["text"] as? String == "two\nthree")
        #expect(part["firstLine"] as? Int == 2)
        #expect((part["at"] as? [String: Any])?["text"] as? String == "three")

        #expect(throws: ReelError.self) {
            try Recorder.screenFile(CodeFile(url: url, lines: 3 ... 9, at: nil))
        }
    }
}

/// Records code screens for real: a page nobody sees needs no permission, so these run everywhere.
@Suite(.serialized)
struct ScreenRecordingTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-screen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func write(_ name: String, _ text: String) throws -> URL {
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func record(_ name: String, _ script: String) async throws -> (Take, TakeLocation) {
        let url = try write(name, script)
        let tape = try Tape.parse(script, relativeTo: folder)
        let location = TakeLocation(tape: url)
        let take = try await Recorder.record(tape, into: location, log: { _ in })
        return (take, location)
    }

    @Test func theSameReelDrawsTheSameTake() async throws {
        _ = try write("Player.swift", Self.swift)
        let script = """
        Screen code
        Set Viewport 640x360
        Set FrameRate 30
        Output a.mp4
        Code Player.swift
        Go "func play"
        Mark "rate" 1
        Callout "speed" "how fast"
        Focus lines 3-6
        Key end
        Key return
        Type "print(rate)"
        Sleep 300ms
        """
        let (first, one) = try await record("one.reel", script)
        let (second, two) = try await record("two.reel", script)
        #expect(first == second)
        #expect(first.width == 1280 && first.height == 720)
        #expect(first.events.count == 9)

        let a = try await frames(AVURLAsset(url: one.movie))
        let b = try await frames(AVURLAsset(url: two.movie))
        #expect(a.count == b.count)
        #expect(a.map(\.time) == b.map(\.time))
        for (x, y) in zip(a, b) {
            #expect(x.difference(y) < 0.5, "frame at \(x.time) s differs by \(x.difference(y))")
        }
        // Typing moved the caret along the line, and the track says so.
        let caret = try #require(first.cursor)
        #expect(caret.count > 10)
        #expect(try #require(caret.last).x > caret[caret.count - 12].x)
    }

    @Test func javaIsColouredAndPlainTextIsNot() async throws {
        let text = "public class Player {\n    private final int rate = 2;\n}\n"
        _ = try write("Player.java", text)
        _ = try write("Player.txt", text)
        let accent = (r: 242, g: 176, b: 76)
        func keywords(_ name: String) async throws -> Int {
            let (_, location) = try await record("\(name).reel", """
            Screen code
            Set Viewport 640x360
            Output a.mp4
            Code \(name)
            Sleep 200ms
            """)
            let last = try #require(try await frames(AVURLAsset(url: location.movie)).last)
            return last.count(near: accent)
        }
        let java = try await keywords("Player.java")
        let plain = try await keywords("Player.txt")
        #expect(java > plain + 500, "java \(java), plain text \(plain)")
    }

    @Test func aPlaceThatIsNotThereNamesItsLine() async throws {
        _ = try write("Player.swift", Self.swift)
        let missing = await #expect(throws: ReelError.self) {
            _ = try await record("missing.reel", "Screen code\nOutput a.mp4\nCode Player.swift\nGo \"func pause\"")
        }
        #expect(missing?.description == "line 4: \"func pause\" is not in Player.swift")
        let outside = await #expect(throws: ReelError.self) {
            _ = try await record(
                "outside.reel", "Screen code\nOutput a.mp4\nCode Player.swift lines 2-4\nGo line 50"
            )
        }
        #expect(outside?.description == "line 4: line 50 is not in Player.swift, which shows lines 2-4")
    }

    static let swift = """
    struct Player {
        var rate = 1.0

        func play(speed: Double) {
            let step = speed * rate
            print(step)
        }
    }
    """
}

/// A movie's frames, as written (no frame for a still screen).
private func frames(_ asset: AVAsset) async throws -> [Picture] {
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    reader.add(output)
    reader.startReading()
    var all: [Picture] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width * 4 {
                bytes[y * width * 4 + x] = base[y * row + x]
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        all.append(Picture(time: CMSampleBufferGetPresentationTimeStamp(sample).seconds, bytes: bytes))
    }
    return all
}

private struct Picture {
    let time: Double
    /// BGRA.
    let bytes: [UInt8]

    /// The mean difference of each byte, out of 255.
    func difference(_ other: Picture) -> Double {
        guard bytes.count == other.bytes.count else { return 255 }
        var total = 0
        for i in 0 ..< bytes.count {
            total += abs(Int(bytes[i]) - Int(other.bytes[i]))
        }
        return Double(total) / Double(bytes.count)
    }

    /// How many pixels are close to a colour.
    func count(near colour: (r: Int, g: Int, b: Int)) -> Int {
        var n = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let b = Int(bytes[i]), g = Int(bytes[i + 1]), r = Int(bytes[i + 2])
            if abs(r - colour.r) + abs(g - colour.g) + abs(b - colour.b) < 60 { n += 1 }
        }
        return n
    }
}

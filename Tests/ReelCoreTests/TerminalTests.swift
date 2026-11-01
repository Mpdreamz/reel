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

struct TerminalParsingTests {
    @Test func aTerminalScreen() throws {
        let tape = try parse("""
        Screen terminal
        Output cli.mp4
        Set Columns 100
        Set Rows 30
        Set FontSize 20
        Set WorkingDirectory ..
        Set Redact /sk-[a-z0-9]+/
        Set Redact /password: .*/
        Set Title "reel — a demo"
        Type "swift build"
        Key return
        Key ctrl+c
        Wait /Build (complete|succeeded)/
        Wait quiet
        Wait quiet 2s
        Wait exit
        Mark "Compiling" 1
        Callout "Build complete" "about a minute"
        Say "Done."
        """)
        #expect(tape.launch == .screen(.terminal))
        #expect(!tape.drivesTheApp)
        #expect(tape.terminal.columns == 100 && tape.terminal.rows == 30)
        #expect(tape.fontSize == 20)
        #expect(tape.terminal.workingDirectory?.path == "/tmp")
        #expect(tape.terminal.redactions == ["sk-[a-z0-9]+", "password: .*"])
        #expect(tape.terminal.title == "reel — a demo")
        #expect(Array(tape.steps.map(\.command).prefix(9)) == [
            .type("swift build", pause: nil),
            .key(KeyCombo("return")!, count: 1),
            .key(KeyCombo("ctrl+c")!, count: 1),
            .expect(.output("Build (complete|succeeded)")),
            .expect(.quiet(Tape.defaultQuiet)),
            .expect(.quiet(.seconds(2))),
            .expect(.exit),
            .mark("Compiling", number: 1),
            .callout("Build complete", label: "about a minute"),
        ])
        // The shell starts beside the reel unless the reel says otherwise.
        let plain = try parse("Screen terminal\nOutput a.mp4")
        #expect(plain.terminal.workingDirectory?.path == dir.path)
        #expect(plain.terminal.columns == 80 && plain.terminal.rows == 24)
    }

    @Test(arguments: [
        ("Screen terminal\nSet Viewport 800x600", 2, "a terminal screen's size is Set Columns and Set Rows"),
        (
            "Screen terminal\nSet Size 800x600", 2,
            "Set Size is an app's window; a terminal screen's size is Set Columns and Set Rows"
        ),
        ("Screen code\nSet Columns 80", 2, "Set Columns is for a terminal screen (Screen terminal)"),
        ("Launch x\nSet Redact /x/", 2, "Set Redact is for a terminal screen (Screen terminal)"),
        ("Screen terminal\nSet Columns 10", 2, "Columns must be a whole number from 20 to 400, not '10'"),
        ("Screen terminal\nSet Rows 2", 2, "Rows must be a whole number from 4 to 200, not '2'"),
        ("Screen terminal\nSet Redact sk-", 2, "a pattern is written between slashes: /Build complete/, not 'sk-'"),
        ("Screen terminal\nSet Theme nothing.ghostty", 2, "no theme at /tmp/demos/nothing.ghostty"),
        (
            "Screen terminal\nOutput a.mp4\nCode a.swift", 3,
            "Code is for a code screen: start the reel with Screen code"
        ),
        (
            "Screen terminal\nOutput a.mp4\nWait /(/", 3,
            "/(/ is not a pattern reel can read: The value “(” is invalid."
        ),
        (
            "Screen terminal\nOutput a.mp4\nWait Play", 3,
            "expected Wait /<regex>/, Wait quiet [duration], Wait exit or Wait [marker]"
        ),
        (
            "Screen terminal\nOutput a.mp4\nWait exit now",
            3,
            "expected Wait /<regex>/, Wait quiet [duration], Wait exit or Wait [marker]"
        ),
        (
            "Screen terminal\nOutput a.mp4\nClick \"Play\"", 3,
            "a terminal screen has no app or page to drive; it takes Type, Key, Wait and the rest"
        ),
        (
            "Screen terminal\nOutput a.mp4\nZoom \"Play\"", 3,
            "a terminal screen zooms on a point (Zoom @x,y) or the cursor, not an element"
        ),
        (
            "Screen terminal\nOutput a.mp4\nKey cmd+c", 3,
            "a terminal screen takes the keys backspace, delete, down, end, enter, esc, escape, forwarddelete, home, "
                + "left, pagedown, pageup, return, right, space, tab, up and ctrl+<letter>, not cmd+c"
        ),
        (
            "Screen terminal\nOutput a.mp4\nSet Columns social ? 56 : 100",
            3,
            "Columns cannot differ by profile: it is fixed when recording"
        ),
    ] as [(String, Int, String)])
    func refusals(text: String, line: Int, message: String) {
        #expect(failure(text) == TapeError(line: line, message: message))
    }

    @Test func keysAsTheShellReadsThem() {
        #expect(TerminalKeys.bytes(for: KeyCombo("return")!) == "\r")
        #expect(TerminalKeys.bytes(for: KeyCombo("up")!) == "\u{1b}[A")
        #expect(TerminalKeys.bytes(for: KeyCombo("backspace")!) == "\u{7f}")
        #expect(TerminalKeys.bytes(for: KeyCombo("ctrl+c")!) == "\u{03}")
        #expect(TerminalKeys.bytes(for: KeyCombo("ctrl+a")!) == "\u{01}")
        #expect(TerminalKeys.bytes(for: KeyCombo("cmd+c")!) == nil)
        #expect(TerminalKeys.bytes(for: KeyCombo("shift+return")!) == nil)
    }

    @Test func aCharacterSplitAcrossTwoReadsWaitsForTheRest() {
        let arrow = Array("❯".utf8) // three bytes
        #expect(TerminalSession.completeLength(Array("ab".utf8)) == 2)
        #expect(TerminalSession.completeLength(Array("a".utf8) + arrow) == 4)
        #expect(TerminalSession.completeLength(Array("a".utf8) + arrow.prefix(2)) == 1)
        #expect(TerminalSession.completeLength(Array("a".utf8) + arrow.prefix(1)) == 1)
        #expect(TerminalSession.completeLength(Array("é".utf8)) == 2)
    }

    @Test func waitsReadTextWithoutColoursOrMarks() {
        let printed = "\u{1b}[36mterm\u{1b}[0m \u{1b}]133;D;0\u{07}\u{1b}[1mBuild\u{1b}[0m complete\r\n"
        #expect(TerminalSession.plain(printed) == "term Build complete\n")
    }

    @Test func ghosttyThemesBecomeXtermThemes() throws {
        let theme = TerminalTheme.parse("""
        # a theme
        background = 101010
        foreground = #EEEEEE
        cursor-color = F2B04C
        palette = 0=#000000
        palette = 9=#ff5555
        palette = 16=#123456
        font-size = 14
        """)
        #expect(theme == [
            "background": "#101010", "foreground": "#EEEEEE", "cursor": "#F2B04C", "black": "#000000",
            "brightRed": "#ff5555",
        ])
        // reel's own is the brand's Ghostty theme.
        let brand = try String(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appending(path: "design/brand/themes/reel-dark.ghostty"), encoding: .utf8
        )
        #expect(TerminalTheme.parse(TerminalTheme.reel) == TerminalTheme.parse(brand))
        #expect(TerminalTheme.parse(TerminalTheme.reel).count == 22)
    }
}

/// Runs shells and draws terminals for real: a pseudo-terminal and a page nobody sees need no permission, so these
/// run everywhere zsh does.
@Suite(.serialized)
struct TerminalRecordingTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-terminal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func record(_ name: String, _ script: String) async throws -> (Take, TakeLocation) {
        let url = folder.appending(path: name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        let tape = try Tape.parse(script, relativeTo: folder)
        let location = TakeLocation(tape: url)
        return try await (Recorder.record(tape, into: location, log: { _ in }), location)
    }

    @Test func aShellRunsWhatIsTypedAndWaitsForIt() async throws {
        try "hello".write(to: folder.appending(path: "greeting.txt"), atomically: true, encoding: .utf8)
        let (take, location) = try await record("run.reel", """
        Screen terminal
        Set Columns 40
        Set Rows 8
        Output a.mp4
        Type@5ms "cat greeting.txt; echo"
        Key return
        Wait /hello/
        Wait exit
        Type@0ms "sleep 0.5; echo ok-done"
        Key return
        Wait /ok-done/
        Wait quiet 300ms
        """)
        #expect(take.events.map(\.line) == [5, 6, 7, 8, 9, 10, 11, 12])
        // Waiting for the output took as long as the sleep before it: the command line, which says ok-done too, does
        // not count, even typed all at once.
        let enter = take.events[5], done = take.events[6]
        #expect(done.endMs - enter.startMs >= 480)
        // And a quiet wait waits for quiet.
        #expect(take.events[7].endMs - take.events[7].startMs >= 200)
        #expect(FileManager.default.fileExists(atPath: location.movie.path))
        #expect(take.cursor?.isEmpty == false)
    }

    @Test func aWaitThatTimesOutSaysWhatWasPrinted() async throws {
        let error = await #expect(throws: ReelError.self) {
            _ = try await record("timeout.reel", """
            Screen terminal
            Set WaitTimeout 1s
            Output a.mp4
            Type@5ms "echo almost there"
            Key return
            Wait /never/
            """)
        }
        let message = try #require(error?.description)
        #expect(message.hasPrefix("line 6: waited 1s for /never/; the last lines were:"))
        #expect(message.contains("almost there"))
    }

    @Test func theSameOutputDrawsTheSameTake() async throws {
        let tape = try Tape.parse("""
        Screen terminal
        Set Columns 40
        Set Rows 6
        Set FrameRate 30
        Output a.mp4
        """, relativeTo: folder)
        let output: [(ms: Int, text: String)] = [
            (0, "\u{1b}[36mreel\u{1b}[0m \u{1b}[33m❯\u{1b}[0m "), (200, "l"), (260, "s"), (330, "\r\n"),
            (400, "\u{1b}[1mPackage.swift\u{1b}[0m  Sources  \u{1b}[34mTests\u{1b}[0m\r\n"),
            (420, "\u{1b}[36mreel\u{1b}[0m \u{1b}[33m❯\u{1b}[0m "),
        ]
        let pointers: [(ms: Int, line: Int, step: Pointer)] = [
            (500, 7, .mark("Sources", 1)), (600, 8, .callout("Tests", "the tests")),
        ]
        func draw(_ name: String) async throws -> (Take, [Picture]) {
            let location = TakeLocation(tape: folder.appending(path: "\(name).reel"))
            let take = try await Recorder.drawTerminal(
                output, pointers: pointers, until: 1000, events: [], tape: tape, folder: folder, into: location,
                log: { _ in }
            )
            return try await (take, frames(AVURLAsset(url: location.movie)))
        }
        let (first, a) = try await draw("one")
        let (second, b) = try await draw("two")
        #expect(first == second)
        #expect(a.count > 4)
        #expect(a.map(\.time) == b.map(\.time))
        for (x, y) in zip(a, b) {
            #expect(x.difference(y) < 0.5, "frame at \(x.time) s differs by \(x.difference(y))")
        }
        // The mark draws reel's amber.
        let lastFrame = try #require(a.last), firstFrame = try #require(a.first)
        #expect(lastFrame.count(near: (242, 176, 76)) > firstFrame.count(near: (242, 176, 76)))
    }

    @Test func aMarkThatIsNotOnScreenNamesItsLine() async throws {
        let tape = try Tape.parse("Screen terminal\nOutput a.mp4", relativeTo: folder)
        let error = await #expect(throws: ReelError.self) {
            _ = try await Recorder.drawTerminal(
                [(0, "hello\r\n")], pointers: [(100, 9, .mark("goodbye", nil))], until: 300, events: [],
                tape: tape, folder: folder, into: TakeLocation(tape: folder.appending(path: "m.reel")), log: { _ in }
            )
        }
        #expect(error?.description == "line 9: \"goodbye\" is not on the terminal's screen")
    }

    @Test @MainActor func aMarkScrollsUpWithItsLine() async throws {
        let page = try await ScreenPage("terminal.html", size: CGSize(width: 1200, height: 800), options: [
            "columns": 40, "rows": 4, "fontSize": 16, "theme": TerminalTheme.load(nil), "title": "t",
        ])
        try await page.step("return reelScreen.layout()")
        func top() async throws -> String? {
            _ = try await page.pump(16)
            return try await page.call(
                "const m = document.querySelector('.mark'); return m.style.display === 'none' ? 'gone' : m.style.top"
            ) as? String
        }
        try await page.step("await reelScreen.feed('one\\r\\ntwo\\r\\n'); return null")
        try await page.step("return reelScreen.mark('two', 1)")
        let before = try #require(try await top())
        try await page.step("await reelScreen.feed('three\\r\\nfour\\r\\n'); return null")
        let after = try #require(try await top())
        #expect(Double(after.dropLast(2))! < Double(before.dropLast(2))!, "\(before) then \(after)")
        try await page.step("await reelScreen.feed('4\\r\\n5\\r\\n6\\r\\n'); return null")
        #expect(try await top() == "gone")
    }

    @Test @MainActor func redactedTextIsCoveredEvenAsItIsTyped() async throws {
        let page = try await ScreenPage("terminal.html", size: CGSize(width: 1200, height: 800), options: [
            "columns": 40, "rows": 4, "fontSize": 16, "theme": TerminalTheme.load(nil), "title": "t",
            "redactions": ["sk-[a-z0-9]+"],
        ])
        try await page.step("return reelScreen.layout()")
        func masks() async throws -> [String] {
            _ = try await page.pump(16)
            return try await page.call(
                "return [...document.querySelectorAll('.redact')].map((m) => m.textContent)"
            ) as? [String] ?? []
        }
        // A page nobody sees is never focused, and still draws its cursor.
        _ = try await page.pump(16)
        #expect(try await page.call("return document.querySelectorAll('.xterm-cursor').length") as? Int == 1)
        // Typed a character at a time, as the shell echoes it: covered from the first character that matches.
        try await page.step("await reelScreen.feed('export T=sk-'); return null")
        #expect(try await masks() == [])
        try await page.step("await reelScreen.feed('a'); return null")
        #expect(try await masks() == ["••••"])
        try await page.step("await reelScreen.feed('bc123'); return null")
        #expect(try await masks() == ["•••••••••"])
        try await page.step("await reelScreen.feed('\\r\\nsk-zz9 and sk-q\\r\\n'); return null")
        let lines = try await masks()
        #expect(lines.sorted() == ["•••••••••", "••••••", "••••"].sorted())
    }
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

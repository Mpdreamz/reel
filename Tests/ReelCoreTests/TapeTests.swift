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

struct TapeTests {
    @Test func parsesAFullTape() throws {
        let tape = try parse("""
        # A demo
        Output demo.mp4
        Output "out/with space.mov"   # trailing comment
        Set FrameRate 30
        Set Audio off

        Launch com.example.musicbox
        Sleep 500ms
        Sleep 2s
        """)
        #expect(tape.outputs == [
            Output(url: URL(fileURLWithPath: "/tmp/demos/demo.mp4"), format: .mp4),
            Output(url: URL(fileURLWithPath: "/tmp/demos/out/with space.mov"), format: .mov),
        ])
        #expect(tape.frameRate == 30)
        #expect(tape.audio == false)
        #expect(tape.launch == .bundleID("com.example.musicbox"))
        #expect(tape.steps == [
            Step(line: 8, source: "Sleep 500ms", command: .sleep(.milliseconds(500))),
            Step(line: 9, source: "Sleep 2s", command: .sleep(.seconds(2))),
        ])
    }

    @Test func defaults() throws {
        let tape = try parse("Output a.mp4\nLaunch com.example.app")
        #expect(tape.frameRate == 60)
        #expect(tape.audio == true)
        #expect(tape.steps.isEmpty)
    }

    @Test func launchTakesAnAppPath() throws {
        #expect(try parse("Output a.mp4\nLaunch build/Musicbox.app").launch
            == .app(URL(fileURLWithPath: "/tmp/demos/build/Musicbox.app")))
        #expect(try parse("Output a.mp4\nLaunch \"/Applications/Music Box.app\"").launch
            == .app(URL(fileURLWithPath: "/Applications/Music Box.app")))
    }

    @Test(arguments: [
        ("500ms", Duration.milliseconds(500)),
        ("2s", .seconds(2)),
        ("1.5s", .milliseconds(1500)),
        ("3", .seconds(3)),
        ("0.25", .milliseconds(250)),
        ("1m", .seconds(60)),
        ("0s", .zero),
    ])
    func durations(text: String, expected: Duration) {
        #expect(Tape.parseDuration(text) == expected)
    }

    @Test(arguments: ["", "s", "ms", "-1s", "two", "1h", ".5s", "1.5.2s", "nan", "inf"])
    func notDurations(text: String) {
        #expect(Tape.parseDuration(text) == nil)
    }

    @Test(arguments: [
        ("Output a.mp4\nLaunch x\nsleep 1s", 3, "unknown command 'sleep'; did you mean Sleep?"),
        (
            "Output a.mp4\nLaunch x\nTypo",
            3,
            "unknown command 'Typo'; expected one of Output, Set, Launch, Sleep, Click, Wait, Type, Key, Scroll, Caption"
        ),
        ("Launch x\nSleep 1s\nOutput a.mp4", 3, "Output is setup and must come before the first step (line 2)"),
        ("Output a.mp4\nSleep 1s\nLaunch x", 3, "Launch is setup and must come before the first step (line 2)"),
        ("Output a.mp4\nLaunch x\nLaunch y", 3, "a tape launches one app; line 2 already does"),
        ("Output a.gif\nLaunch x", 1, "unsupported output type '.gif'; expected .mp4 or .mov"),
        ("Output a.mp4\nOutput ./a.mp4\nLaunch x", 2, "./a.mp4 is already an Output"),
        ("Output a.mp4 b.mp4", 1, "expected Output <path>"),
        ("Output a.mp4\nLaunch", 2, "expected Launch <bundle id or .app path>"),
        ("Set FrameRate 0", 1, "FrameRate must be a whole number from 1 to 120, not '0'"),
        ("Set FrameRate 30.5", 1, "FrameRate must be a whole number from 1 to 120, not '30.5'"),
        ("Set Audio yes", 1, "Audio must be on or off, not 'yes'"),
        (
            "Set Speed 2",
            1,
            "unknown setting 'Speed'; expected FrameRate, Audio, Size, TypingSpeed, WaitTimeout, KeyBadges or ClickRipples"
        ),
        ("Set Audio", 1, "expected Set <setting> <value>"),
        (
            "Output a.mp4\nLaunch x\nSleep soon",
            3,
            "'soon' is not a duration; write 500ms, 2s, 1.5s or a number of seconds"
        ),
        ("Output \"a.mp4", 1, "unterminated quote"),
    ])
    func errorsNameTheLine(text: String, line: Int, message: String) {
        #expect(failure(text) == TapeError(line: line, message: message))
    }

    @Test func parsesDrivingTheApp() throws {
        let tape = try parse("""
        Output a.mp4
        Set Size 1280x800
        Set TypingSpeed 20ms
        Set WaitTimeout 5s
        Launch com.example.app
        Wait "Library"
        Click #play
        Click "#not-an-id"
        Click @120,80.5
        Type "hello \\"world\\""
        Type@100ms slow
        Key cmd+shift+z
        Key down 3
        Scroll down 5
        Scroll up
        Scroll down 3 #list
        Scroll left "Wide table"
        Scroll right @10,20
        """)
        #expect(tape.size == CGSize(width: 1280, height: 800))
        #expect(tape.typingSpeed == .milliseconds(20))
        #expect(tape.waitTimeout == .seconds(5))
        #expect(tape.drivesTheApp)
        #expect(tape.steps.map(\.command) == [
            .wait(.label("Library")),
            .click(.identifier("play")),
            .click(.label("#not-an-id")),
            .click(.point(CGPoint(x: 120, y: 80.5))),
            .type("hello \"world\"", pause: nil),
            .type("slow", pause: .milliseconds(100)),
            .key(KeyCombo("cmd+shift+z")!, count: 1),
            .key(KeyCombo("down")!, count: 3),
            .scroll(.down, lines: 5, over: nil),
            .scroll(.up, lines: 1, over: nil),
            .scroll(.down, lines: 3, over: .identifier("list")),
            .scroll(.left, lines: 1, over: .label("Wide table")),
            .scroll(.right, lines: 1, over: .point(CGPoint(x: 10, y: 20))),
        ])
        // The timeline keeps each line as written.
        #expect(tape.steps[4].source == #"Type "hello \"world\"""#)
        #expect(tape.steps[2].source == ##"Click "#not-an-id""##)
    }

    @Test func comments() throws {
        let tape = try parse("""
        # a comment
        Output a.mp4 # after a space
        Launch x
        Click #play # an identifier, then a comment
        """)
        #expect(tape.steps.map(\.command) == [.click(.identifier("play"))])
    }

    @Test func onlySleepingNeedsNoAccessibility() throws {
        #expect(try !parse("Output a.mp4\nLaunch x\nSleep 1s").drivesTheApp)
        #expect(try parse("Output a.mp4\nSet Size 800x600\nLaunch x").drivesTheApp)
    }

    @Test(arguments: [
        ("Set Size 1280", "Size must be <width>x<height> in points, such as 1280x800, not '1280'"),
        ("Set Size 50x50", "Size must be <width>x<height> in points, such as 1280x800, not '50x50'"),
        ("Set TypingSpeed fast", "'fast' is not a duration; write 500ms, 2s, 1.5s or a number of seconds"),
        ("Click", "expected Click \"<label>\", Click #<identifier> or Click @x,y"),
        ("Click a b", "expected Click \"<label>\", Click #<identifier> or Click @x,y"),
        ("Click @1", "'@1' is not a point; write @x,y in points from the window's top left, such as @120,80"),
        ("Click @-1,5", "'@-1,5' is not a point; write @x,y in points from the window's top left, such as @120,80"),
        ("Click # a comment", "expected Click \"<label>\", Click #<identifier> or Click @x,y"),
        ("Wait @1,2", "Wait needs an element to wait for, not a point"),
        ("Wait", "expected Wait \"<label>\" or Wait #<identifier>"),
        ("Type", "expected Type \"<text>\""),
        ("Type@soon hi", "'soon' is not a duration; write 500ms, 2s, 1.5s or a number of seconds"),
        ("Sleep@1s 1s", "Sleep takes no @option"),
        ("Key", "expected Key <combo> [count]"),
        ("Key cmd+nope", "'cmd+nope' is not a key; write a key name such as return or a, with modifiers: cmd+s"),
        ("Key a 0", "the count must be a whole number from 1 to 100, not '0'"),
        ("Scroll sideways", "'sideways' is not a direction; expected up, down, left or right"),
        ("Scroll down 0", "the count must be a whole number from 1 to 100, not '0'"),
        ("Scroll down 2 #a #b", "expected Scroll <up|down|left|right> [lines] [element or @x,y]"),
        ("Scroll down #a 2", "expected Scroll <up|down|left|right> [lines] [element or @x,y]"),
    ])
    func drivingErrors(command: String, message: String) {
        let line = command.hasPrefix("Set") ? 2 : 3
        let text = command.hasPrefix("Set") ? "Output a.mp4\n\(command)\nLaunch x" : "Output a.mp4\nLaunch x\n\(command)"
        #expect(failure(text) == TapeError(line: line, message: message))
    }

    @Test func wholeTapeErrors() {
        #expect(failure("Launch x") == TapeError(message: "the tape has no Output"))
        #expect(failure("Output a.mp4\n# no launch") == TapeError(message: "the tape has no Launch"))
        #expect(TapeError(line: 4, message: "boom").description == "line 4: boom")
    }

    @Test func takeLivesNextToTheTape() {
        let location = TakeLocation(tape: URL(fileURLWithPath: "/tmp/demos/intro.tape"))
        #expect(location.movie.path == "/tmp/demos/.reel/intro/take.mov")
        #expect(location.timeline.path == "/tmp/demos/.reel/intro/take.json")
    }
}

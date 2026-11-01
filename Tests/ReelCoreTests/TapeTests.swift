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
        Launch com.example.musicbox
        Output demo.mp4
        Output "out/with space.mov"   # trailing comment
        Set FrameRate 30
        Set Audio off

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

    @Test func gifs() throws {
        let tape = try parse("Launch x\nOutput a.gif\nSet GifFrameRate 10\nSet GifWidth 640\nSet GifColors 64")
        #expect(tape.outputs.map(\.format) == [.gif])
        #expect(tape.gifFrameRate == 10)
        #expect(tape.gifWidth == 640)
        #expect(tape.gifColors == 64)
        #expect(!Output.Format.gif.hasSound)
    }

    @Test func encoding() throws {
        let tape = try parse("Launch x\nOutput a.mp4\nSet Quality 40\nSet Codec HEVC\nSet VideoWidth 1920")
        #expect(tape.encoding == Encoding(quality: 40, codec: .hevc, width: 1920))
    }

    @Test func defaults() throws {
        let tape = try parse("Launch com.example.app\nOutput a.mp4")
        #expect(tape.gifFrameRate == 15)
        #expect(tape.gifWidth == 800)
        #expect(tape.gifColors == 256)
        #expect(tape.encoding == Encoding(quality: 65, codec: .h264, width: nil))
        #expect(tape.frameRate == 60)
        #expect(tape.audio == true)
        #expect(tape.steps.isEmpty)
    }

    @Test func pathsResolveInsideTheDirectoryWithOrWithoutASlash() throws {
        for directory in ["/tmp/demos", "/tmp/demos/"] {
            let tape = try Tape.parse("Launch x\nOutput out/a.mp4", relativeTo: URL(fileURLWithPath: directory))
            #expect(tape.outputs[0].url.path == "/tmp/demos/out/a.mp4")
        }
    }

    @Test func aBundleIDMayEndInApp() throws {
        #expect(try parse("Launch dev.musicbox.app\nOutput a.mp4").launch == .bundleID("dev.musicbox.app"))
        #expect(try parse("Launch ./Musicbox.app\nOutput a.mp4").launch
            == .app(URL(fileURLWithPath: "/tmp/demos/Musicbox.app")))
    }

    @Test func launchTakesAnAppPath() throws {
        #expect(try parse("Launch build/Musicbox.app\nOutput a.mp4").launch
            == .app(URL(fileURLWithPath: "/tmp/demos/build/Musicbox.app")))
        #expect(try parse("Launch \"/Applications/Music Box.app\"\nOutput a.mp4").launch
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
        ("Launch x\nOutput a.mp4\nsleep 1s", 3, "unknown command 'sleep'; did you mean Sleep?"),
        (
            "Launch x\nOutput a.mp4\nTypo",
            3,
            "unknown command 'Typo'; expected one of Output, Set, Launch, Sleep, Click, Wait, Type, Key, Scroll, Caption, Say, Zoom, Speed, Hide, Show, Intro, Outro, Open, Screen, Code, Go, Focus, Mark, Callout, Include, Split, Pane, Peek, Link, Diff, Morph, With"
        ),
        ("Launch x\nSleep 1s\nOutput a.mp4", 3, "Output is setup and must come before the first step (line 2)"),
        (
            "Output a.mp4\nLaunch x",
            1,
            "a reel starts with Launch <app>, Open <url>, Screen code, Screen terminal or Include <scene.reel> (after any Import lines), which says what it records"
        ),
        (
            "# a demo\nSleep 1s\nLaunch x",
            2,
            "a reel starts with Launch <app>, Open <url>, Screen code, Screen terminal or Include <scene.reel> (after any Import lines), which says what it records"
        ),
        ("Launch x\nOutput a.mp4\nLaunch y", 3, "a reel launches one app; line 1 already does"),
        ("Launch x\nOutput a.webm", 2, "unsupported output type '.webm'; expected .mp4, .mov or .gif"),
        ("Launch x\nSet GifFrameRate 60", 2, "GifFrameRate must be a whole number from 1 to 50, not '60'"),
        ("Launch x\nSet GifWidth 50", 2, "GifWidth must be a whole number of pixels from 100 to 4000, not '50'"),
        ("Launch x\nSet GifColors 1", 2, "GifColors must be a whole number from 2 to 256, not '1'"),
        ("Launch x\nSet GifColors 257", 2, "GifColors must be a whole number from 2 to 256, not '257'"),
        ("Launch x\nSet Quality 0", 2, "Quality must be a whole number from 1 to 100, not '0'"),
        ("Launch x\nSet Quality 101", 2, "Quality must be a whole number from 1 to 100, not '101'"),
        ("Launch x\nSet Codec av1", 2, "Codec must be h264, hevc or prores, not 'av1'"),
        ("Launch x\nSet VideoWidth 99", 2, "VideoWidth must be a whole number of pixels from 100 to 8000, not '99'"),
        ("Launch x\nOutput a.mp4\nOutput ./a.mp4", 3, "./a.mp4 is already an Output"),
        ("Launch x\nOutput a.mp4 b.mp4", 2, "expected Output <path>"),
        ("Launch", 1, "expected Launch <bundle id or .app path>"),
        ("Launch x\nSet FrameRate 0", 2, "FrameRate must be a whole number from 1 to 120, not '0'"),
        ("Launch x\nSet FrameRate 30.5", 2, "FrameRate must be a whole number from 1 to 120, not '30.5'"),
        ("Launch x\nSet Audio yes", 2, "Audio must be on or off, not 'yes'"),
        (
            "Launch x\nSet Speed 2",
            2,
            "unknown setting 'Speed'; expected FrameRate, Audio, Size, TypingSpeed, WaitTimeout, KeyBadges, ClickRipples, Quality, Codec, VideoWidth, VideoFrameRate, MaxSize, MaxLength, Shape, Formats, Profiles, GifFrameRate, GifWidth, GifColors, Voice, VoiceServer, VoiceSeed, VoiceLanguage, Ducking, VoiceVolume, AppVolume, Subtitles, ZoomEasing, ZoomDuration, IntroBackground, OutroBackground, Browser, Viewport, FontSize, Columns, Rows, WorkingDirectory, Theme, Redact, Title, Background or Padding"
        ),
        ("Launch x\nSet Audio", 2, "expected Set <setting> <value>"),
        (
            "Launch x\nOutput a.mp4\nSleep soon",
            3,
            "'soon' is not a duration; write 500ms, 2s, 1.5s or a number of seconds"
        ),
        ("Output \"a.mp4", 1, "unterminated quote"),
    ])
    func errorsNameTheLine(text: String, line: Int, message: String) {
        #expect(failure(text) == TapeError(line: line, message: message))
    }

    @Test func escapesInQuotedText() throws {
        let tape = try parse("Launch x\nOutput a.mp4\n" + #"Type "one\ntwo \"three\" back\\slash\tend""#)
        #expect(tape.steps.first?.command == .type("one\ntwo \"three\" back\\slash\tend", pause: nil))
        // The line as written, escapes and all: a take compares it.
        #expect(tape.steps.first?.source == #"Type "one\ntwo \"three\" back\\slash\tend""#)
    }

    @Test func parsesDrivingTheApp() throws {
        let tape = try parse("""
        Launch com.example.app
        Output a.mp4
        Set Size 1280x800
        Set TypingSpeed 20ms
        Set WaitTimeout 5s
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
        Launch x
        Output a.mp4 # after a space
        Click #play # an identifier, then a comment
        """)
        #expect(tape.steps.map(\.command) == [.click(.identifier("play"))])
    }

    @Test func onlySleepingNeedsNoAccessibility() throws {
        #expect(try !parse("Launch x\nOutput a.mp4\nSleep 1s").drivesTheApp)
        #expect(try parse("Launch x\nOutput a.mp4\nSet Size 800x600").drivesTheApp)
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
        ("Wait", "expected Wait \"<label>\", Wait #<identifier> or Wait [marker]"),
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
        let line = 3
        let text = "Launch x\nOutput a.mp4\n\(command)"
        #expect(failure(text) == TapeError(line: line, message: message))
    }

    @Test func narration() throws {
        let tape = try parse("""
        Launch x
        Output a.mp4
        Set Voice voicebox:narrator
        Set VoiceServer http://studio.local:9000
        Set VoiceSeed 7
        Set VoiceLanguage nl
        Set Ducking 25%
        Set VoiceVolume 90%
        Set AppVolume 50%
        Set Subtitles on
        Say "This is Musicbox."
        Say@over "Pick a track, [pick] then press [play] space."
        Wait [pick]
        Click "Midnight City"
        Wait [play]
        Key space
        """)
        #expect(tape.voice.source == .voicebox("narrator"))
        #expect(tape.voice.server == URL(string: "http://studio.local:9000"))
        #expect(tape.voice.seed == 7)
        #expect(tape.voice.language == "nl")
        #expect(tape.voice.ducking == 0.25)
        #expect(tape.voice.voiceVolume == 0.9)
        #expect(tape.voice.appVolume == 0.5)
        #expect(tape.voice.subtitles)
        guard case let .say(first, over) = tape.steps[0].command, case let .say(second, true) = tape.steps[1].command
        else { Issue.record("expected two Says"); return }
        #expect(!over)
        #expect(first.pieces == ["This is Musicbox."])
        #expect(second.pieces == ["Pick a track,", "then press", "space."])
        #expect(second.markers == ["pick", "play"])
        #expect(second.text == "Pick a track, then press space.")
        #expect(tape.steps[2].command == .reach("pick"))
        #expect(tape.steps[4].command == .reach("play"))
        // Narration needs no Accessibility, and recording performs it.
        #expect(try !parse("Launch x\nOutput a.mp4\nSay \"Hi\"").drivesTheApp)
        #expect(tape.actions.count == 6)
    }

    @Test func namedVoices() throws {
        let tape = try parse("""
        Launch x
        Output a.mp4
        Set Voice voicebox:Main
        Set Voice guest system:Samantha
        Say "Hello."
        Say@guest "Hi."
        Say@guest,over "And [now] this."
        Say@over,guest "Or this."
        """)
        #expect(tape.voice.source == .voicebox("Main"))
        #expect(tape.voice.named == ["guest": .system("Samantha")])
        let says = tape.steps.compactMap { step -> (String?, Bool)? in
            guard case let .say(speech, over) = step.command else { return nil }
            return (speech.voice, over)
        }
        #expect(says.map(\.0) == [nil, "guest", "guest", "guest"])
        #expect(says.map(\.1) == [false, false, true, true])
        // Each name its own synthesizer; no name, the reel's own voice.
        #expect(tape.voice.synthesizer(for: "guest").fingerprint != tape.voice.synthesizer().fingerprint)
    }

    @Test func voiceDefaults() throws {
        let voice = try parse("Launch x\nOutput a.mp4").voice
        #expect(voice == VoiceSettings())
        #expect(voice.source == .system(nil))
        #expect(voice.server == URL(string: "http://127.0.0.1:17493"))
        #expect(try parse("Launch x\nOutput a.mp4\nSet Voice system:Samantha").voice.source == .system("Samantha"))
    }

    @Test(arguments: [
        ("Say", "expected Say \"<text>\""),
        ("Say \"\"", "Say needs words to speak"),
        ("Say \"[a]\"", "Say needs words to speak"),
        ("Say@under \"Hi\"", "no voice is named under; name one first with Set Voice under <voice>"),
        ("Say@over,over \"Hi\"", "Say takes @over, a voice's name, or both (Say@guest,over), not @over,over"),
        ("Say@a,b \"Hi\"", "Say takes @over, a voice's name, or both (Say@guest,over), not @a,b"),
        ("Say@over, \"Hi\"", "Say takes @over, a voice's name, or both (Say@guest,over), not @over,"),
        (
            "Set Voice over system",
            "'over' cannot name a voice; name it with letters, digits, - and _ (not over), such as Set Voice guest "
                + "voicebox:Bella"
        ),
        (
            "Set Voice g:x system",
            "'g:x' cannot name a voice; name it with letters, digits, - and _ (not over), such as Set Voice guest "
                + "voicebox:Bella"
        ),
        ("Set Voice guest robot", "Voice must be system, system:<voice name> or voicebox:<profile>, not 'robot'"),
        ("Set Voice a b c", "expected Set <setting> <value>"),
        ("Say \"Press [play now\"", "a [ in the text has no ]"),
        (
            "Say \"Press [play now]\"",
            "'[play now]' is not a marker; name it with letters, digits, - and _, such as [play]"
        ),
        ("Say@over \"a [x] b [x] c\"", "[x] is already a marker on line 3"),
        ("Wait [nope]", "no Say before this has a marker [nope]"),
        ("Set Voice robot", "Voice must be system, system:<voice name> or voicebox:<profile>, not 'robot'"),
        ("Set Voice voicebox:", "Voice must be system, system:<voice name> or voicebox:<profile>, not 'voicebox:'"),
        ("Set Ducking 25", "Ducking must be a percentage from 0% to 100%, not '25'"),
        ("Set AppVolume 120%", "AppVolume must be a percentage from 0% to 100%, not '120%'"),
        ("Set VoiceServer studio", "VoiceServer must be an http URL, such as http://127.0.0.1:17493, not 'studio'"),
        ("Set VoiceLanguage english", "VoiceLanguage must be a two letter code such as en or nl, not 'english'"),
        ("Set VoiceSeed -1", "VoiceSeed must be a whole number from 0, not '-1'"),
    ])
    func narrationErrors(command: String, message: String) {
        let line = 3
        let text = "Launch x\nOutput a.mp4\n\(command)"
        #expect(failure(text) == TapeError(line: line, message: message))
    }

    @Test func aMarkerOfABlockingSayHasPassed() {
        #expect(failure("Launch x\nOutput a.mp4\nSay \"Now [go]\"\nWait [go]") == TapeError(
            line: 4,
            message: "the Say on line 3 waits until it ends, so [go] has passed by now; write Say@over to act while it speaks"
        ))
    }

    @Test func wholeTapeErrors() {
        #expect(failure("Launch x") == TapeError(message: "the reel has no Output"))
        #expect(failure("# nothing but a comment") == TapeError(message: Tape.preface))
        #expect(failure("") == TapeError(message: Tape.preface))
        #expect(TapeError(line: 4, message: "boom").description == "line 4: boom")
    }

    @Test func onlyAReelFilePlays() {
        #expect(throws: TapeError(message: "demo.tape is not a reel script; those are .reel files")) {
            try Tape.load(URL(fileURLWithPath: "/d/demo.tape"))
        }
    }

    @Test func takeLivesNextToTheTape() {
        let location = TakeLocation(tape: URL(fileURLWithPath: "/tmp/demos/intro.reel"))
        #expect(location.movie.path == "/tmp/demos/.reel/intro/take.mov")
        #expect(location.timeline.path == "/tmp/demos/.reel/intro/take.json")
    }
}

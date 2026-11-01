import CoreGraphics
import Foundation

/// A parsed `.reel`: what to launch, how to capture it, what to do once recording, and where the outputs go.
public struct Tape: Equatable, Sendable {
    public var outputs: [Output]
    public var frameRate: Int
    public var audio: Bool
    /// The window's size in points, set before recording; nil keeps the size it opened with.
    public var size: CGSize?
    /// The pause after each typed character, unless a `Type@<duration>` says otherwise.
    public var typingSpeed: Duration
    /// How long `Wait` waits, and how long `Click` looks for its element.
    public var waitTimeout: Duration
    /// Draw a badge for each `Key` step (render time).
    public var keyBadges: Bool
    /// Draw a ripple where each `Click` lands (render time).
    public var clickRipples: Bool
    /// Frames a second in a `.gif` Output; still stretches become one frame whatever the rate.
    public var gifFrameRate: Int
    /// Pixels wide of a `.gif` Output, at most the video's own width.
    public var gifWidth: Int
    /// Colours in a `.gif` Output's palette, 2–256: fewer make a smaller file.
    public var gifColors: Int
    /// How a movie Output is compressed (`Set Quality`, `Set Codec`, `Set VideoWidth`).
    public var encoding: Encoding
    /// `Set VideoFrameRate`: frames a second in a movie Output, at most the take's; nil keeps the take's.
    public var videoFrameRate: Int?
    /// `Set MaxSize`: the most bytes an Output may be; render fits it under, or fails saying so. nil: no limit.
    public var maxSize: Int?
    /// `Set MaxLength`: the longest a movie or GIF may run, in seconds; longer fails the render. nil: no limit.
    public var maxLength: Double?
    /// `Set Profiles`: the profiles every Output is rendered for, by name; empty renders each Output once, as named.
    public var profiles: [String]
    /// The profile this tape was read for (`with(profile:)`): its settings applied, its Outputs suffixed with its
    /// name and those of a type it does not write left out (in `skipped`).
    public var profile: Profile?
    /// Outputs the profile does not write (`Set Formats`).
    public var skipped: [Output]
    /// The text the tape was read from, to read it again for a profile.
    public var source: Source?
    /// The profiles the tape can render for: the built-in ones, amended and added to by its presets and itself.
    public var known: [Profile]
    /// What reading it found worth saying but not refusing: relative paths that lead out of the git root.
    public var warnings: [String]
    /// Whether a condition tests an Output's type (`gif ? … : …`): then each type is rendered from its own reading.
    public var conditionsOnFormat: Bool

    public struct Source: Equatable, Sendable {
        public var text: String
        public var directory: URL
    }

    /// Who speaks `Say` lines and how they mix with the app's sound.
    public var voice: VoiceSettings
    /// How a `Zoom` moves when it gives none of its own (`Zoom@ease-out`).
    public var zoomTransition: Transition
    /// A title card before the demo and one after it, each moving into the next with its own transition.
    public var intro: Section?
    public var outro: Section?
    /// For a tape that `Open`s a web page.
    public var web: WebSettings
    /// For a terminal screen.
    public var terminal: TerminalSettings
    /// For a sequence: the reels it joins, in order.
    public var scenes: [Scene]
    /// For a reel that records several subjects at once: each one's track.
    public var tracks: [Track]
    /// `Set FontSize`: a code screen's text, in points.
    public var fontSize: Int
    /// `Set Background`: the recording is framed on it in every output; nil frames only outputs with a shape.
    public var background: Background?
    /// Room around a framed recording, as a share of the canvas's shorter side.
    public var padding: Double
    public var launch: LaunchTarget
    /// The commands after setup, in order. Recording starts before the first one.
    public var steps: [Step]
    /// `Set Layout`: how a reel of tracks arranges them to start with; nil puts them side by side.
    public var layout: Layout?

    public static let defaultFrameRate = 60
    public static let defaultTypingSpeed = Duration.milliseconds(50)
    public static let defaultWaitTimeout = Duration.seconds(10)
    public static let defaultGifFrameRate = 15
    public static let defaultGifWidth = 800
    public static let defaultGifColors = 256
    public static let defaultFontSize = 18
    public static let defaultQuiet: Duration = .milliseconds(500)

    /// What every tape starts with, and the error a tape gets when it does not.
    static let preface =
        "a reel starts with Launch <app>, Open <url>, Screen code, Screen terminal or Include <scene.reel> (after any Import lines), which says what it records"

    /// Whether playing the tape needs Accessibility: anything that finds, moves or types into the app.
    public var drivesTheApp: Bool {
        guard !launch.isScreen else { return false }
        return size != nil || steps.contains {
            switch $0.command {
            case .sleep, .caption, .say, .reach, .speed, .hide, .focus, .mark, .callout, .waitFor, .move: false
            case let .zoom(target, _, _): target.isElement
            default: true
            }
        }
    }

    /// The steps recording performs, in order: everything but what only render draws or edits (captions, speed,
    /// trims, zooms that need no element). A take has one timeline event for each.
    public var actions: [Step] {
        steps.filter { !$0.command.isRenderOnly }
    }
}

public struct Output: Equatable, Sendable {
    public enum Format: String, Equatable, Sendable, CaseIterable {
        case mp4, mov, gif

        /// A GIF has no sound.
        public var hasSound: Bool {
            self != .gif
        }
    }

    public var url: URL
    public var format: Format
    /// `Output@16:9 …`: the canvas the recording is framed on; nil for the recording's own shape.
    public var shape: Shape?

    /// A canvas: an aspect ratio (its size worked out from the recording) or an exact size in pixels.
    public enum Shape: Hashable, Sendable, CustomStringConvertible {
        case aspect(Int, Int)
        case size(Int, Int)

        public var description: String {
            switch self {
            case let .aspect(w, h): "\(w):\(h)"
            case let .size(w, h): "\(w)x\(h)"
            }
        }
    }

    public init(url: URL, format: Format, shape: Shape? = nil) {
        self.url = url
        self.format = format
        self.shape = shape
    }
}

public enum LaunchTarget: Equatable, Sendable {
    case bundleID(String)
    case app(URL)
    /// `Open <url>`: a web page, in a browser reel drives over the DevTools protocol.
    case web(URL)
    /// `Screen code`, `Screen terminal`: no app and no page, a screen reel draws itself (see `ScreenPage`).
    case screen(ScreenLayout)
    /// `Include <scene.reel>`: other reels, recorded each on its own and joined (see `Scenes`).
    case sequence
    /// `Screen terminal as term` and its indented steps, `With x.reel as name`: several subjects recorded at once,
    /// each a track of its own, the reel's unindented steps the director's (see `Tracks`).
    case together
    /// `Attach <app> as <name>`: a track recording an app something else opens (a reel run in a terminal track), from
    /// when its window shows. A bundle id, or an app's path.
    case attach(String)

    public var isTogether: Bool {
        self == .together
    }

    public var isSequence: Bool {
        self == .sequence
    }

    /// What it records, in a few words: `Musicbox.app`, `a web page`, `a terminal screen`.
    public var summary: String {
        switch self {
        case let .bundleID(id): id
        case let .app(url): url.lastPathComponent
        case let .web(url): url.host() ?? url.lastPathComponent
        case let .screen(layout): layout.name
        case .sequence: "scenes"
        case .together: "tracks"
        case let .attach(app): "\((app as NSString).lastPathComponent), once something opens it"
        }
    }

    public var isWeb: Bool {
        if case .web = self { true } else { false }
    }

    public var isScreen: Bool {
        if case .screen = self { true } else { false }
    }

    /// The screen a screen reel shows; nil for an app or a page.
    public var screen: ScreenLayout? {
        if case let .screen(layout) = self { layout } else { nil }
    }
}

/// What a screen reel shows: reel's own editor, or a terminal running a shell.
public enum ScreenLayout: String, Equatable, Sendable, CaseIterable {
    case code
    case terminal

    /// For errors: "a code screen".
    var name: String {
        "a \(rawValue) screen"
    }
}

/// `Include[@<transition>] <scene.reel>`: one reel of a sequence, and how the scene before it moves into it (nil for
/// the first, which has nothing before it).
public struct Scene: Equatable, Sendable {
    public var url: URL
    public var transition: SectionTransition?
}

/// One subject of a reel that records several at once: its name, and the reel of its own it plays, written inline (its
/// indented steps) or in a file (`With x.reel as name`).
public struct Track: Equatable, Sendable {
    public var name: String
    /// The line that declares it.
    public var line: Int
    /// The file it was read from; nil for one written inline.
    public var file: URL?
    public var tape: Tape
}

/// A terminal screen's shell and how it is drawn.
public struct TerminalSettings: Equatable, Sendable {
    /// `Set Columns`, `Set Rows`: the terminal's size in characters, which also sizes the screen.
    public var columns = 80
    public var rows = 24
    /// `Set WorkingDirectory`: where the shell starts; nil for the reel's folder.
    public var workingDirectory: URL?
    /// `Set Theme`: a Ghostty theme file; nil for reel's own colours.
    public var theme: URL?
    /// `Set Redact /regex/`: output that matches is drawn as dots, before it is kept.
    public var redactions: [String] = []
    /// `Set Title`: the window's title; nil for the shell and the folder.
    public var title: String?

    public init() {}
}

/// `Wait` on a terminal screen.
public enum TerminalWait: Equatable, Sendable {
    /// `Wait /regex/`: until the output since the last thing typed matches.
    case output(String)
    /// `Wait quiet [duration]`: until nothing is printed for that long.
    case quiet(Duration)
    /// `Wait exit`: until the command running ends and the prompt is back.
    case exit
}

/// `Code <file> [lines a-b] [at …]`: a file opened in a code screen's editor.
public struct CodeFile: Equatable, Sendable {
    public var url: URL
    /// The lines shown, scrolled to and named in the header; nil for the whole file.
    public var lines: ClosedRange<Int>?
    /// Where the cursor goes; nil for the start of `lines` (or of the file).
    public var at: CodeAnchor?
}

/// A place in the open file: a line, or the first match of some text (the cursor goes to its start).
public enum CodeAnchor: Equatable, Sendable {
    case line(Int)
    case text(String)
    /// `hunk 2`: the second run of changes in a diff.
    case hunk(Int)
}

/// `Diff <before> <after>`, `Diff <file> since <revision>`: what a diff compares.
public struct DiffSource: Equatable, Sendable {
    public enum Before: Equatable, Sendable {
        /// Another file: the version before.
        case file(URL)
        /// The file as git has it at a revision (`HEAD~1`, a tag, a commit).
        case revision(String)
    }

    public var before: Before
    public var after: URL
    /// Where the cursor goes: a line of the new file, some text, or a hunk.
    public var at: CodeAnchor?
}

/// Which browser shows a web page. Anything but WebKit is a promise the tape makes: when it cannot be kept, recording
/// refuses rather than fall back.
public enum BrowserChoice: Equatable, Sendable {
    /// WebKit, built into macOS: a view in a window of reel's own. The default.
    case webkit
    /// Any Chromium-based browser reel finds (`Browser.locate`).
    case chromium
    /// That Chromium-based browser.
    case app(URL)
}

public extension BrowserChoice {
    enum Resolved: Equatable, Sendable {
        case webkit
        /// A Chromium-based browser's app.
        case chromium(URL)
    }

    /// What the choice comes to on this Mac, or why it cannot be had: a tape that chose a browser never gets another.
    /// `locate` finds a Chromium-based browser (`Browser.locate`).
    func resolve(locate: () -> URL?, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        throws -> Resolved
    {
        switch self {
        case .webkit:
            return .webkit
        case .chromium:
            guard let app = locate() else {
                throw ReelError(
                    "the reel Sets Browser chromium, but none is installed (Chrome, Chromium, Brave, Edge) or "
                        + "downloaded by Playwright (`npx playwright install chromium`)"
                )
            }
            return .chromium(app)
        case let .app(app):
            guard exists(app) else { throw ReelError("the reel Sets Browser \(app.path), which is not there") }
            return .chromium(app)
        }
    }
}

/// How a web page is shown: in which browser, and how big the page is.
public struct WebSettings: Equatable, Sendable {
    /// Which browser shows the page: WebKit, built into macOS, unless the tape says otherwise.
    public var browser = BrowserChoice.webkit
    /// The page's size in points (CSS pixels).
    public var viewport = CGSize(width: 1280, height: 800)

    public init() {}
}

public struct Step: Equatable, Sendable {
    public var line: Int
    /// The line as written, for the take's timeline.
    public var source: String
    public var command: Command
    /// `… as <name>`: what other reels running with this one wait for (`Wait for <name>`).
    public var name: String?
}

public enum Command: Equatable, Sendable {
    case sleep(Duration)
    /// `Wait for <name>`: until a step of that name, in another reel running with this one, starts (or, `to end`,
    /// has ended). Skipped when this reel runs alone.
    case waitFor(String, end: Bool)
    case click(Target)
    case wait(Target)
    /// `Wait /regex/`, `Wait quiet`, `Wait exit` on a terminal screen.
    case expect(TerminalWait)
    /// Each character, then the pause after it (`Type@<duration>`), nil for the tape's typing speed.
    case type(String, pause: Duration?)
    case key(KeyCombo, count: Int)
    /// Over the target when there is one, else wherever the cursor is (in the window).
    case scroll(ScrollDirection, lines: Int, over: Target?)
    /// Drawn at render time from the end of the action before it: until the next caption, for `duration`, or, with
    /// nil text (`Caption off`), ends the one showing. Recording skips it, so captions change without a new take.
    case caption(String?, duration: Duration?)
    /// Narration. Blocks until the line ends, or with `over` (`Say@over`) carries on while it plays. Lines never
    /// overlap: one starts after the one before has ended.
    case say(Speech, over: Bool)
    /// `Wait [marker]`: until the narration reaches a marker of an earlier `Say@over`.
    case reach(String)
    /// Zooms the picture at render time, easing to it, until the next `Zoom`. An element is found while recording and
    /// followed while the zoom holds; `scale` nil fits it.
    case zoom(ZoomTarget, scale: Double?, transition: Transition?)
    /// `Speed 4x` until `Speed off` (nil): sped up at render time, narrated lines kept at their own pace.
    case speed(Double?)
    /// `Hide` (true) until `Show` (false): left out of the render.
    case hide(Bool)
    /// `Open <url>` after the tape has started: goes to another page.
    case open(URL)
    /// `Code <file>`: opens a file in a code screen's editor.
    case code(CodeFile, transition: SectionTransition?)
    /// `Diff <before> <after>`, `Diff <file> since <revision>`: two versions of a file as one, what changed marked.
    case diff(DiffSource, transition: SectionTransition?)
    /// `Morph <file>`: the file shown turns into this one, the words they share moving to their new places, the rest
    /// fading out and in. `motion` is its easing and length, nil for the default.
    case morph(CodeFile, motion: Transition?)
    /// `Follow`: the pane highlights each line of the reel it shows as that reel runs, somewhere on the channel (a
    /// terminal track running it); `Follow off` (false) stops.
    case follow(Bool)
    /// `Split <file>`: the file in a second pane beside the first, which it makes the active one; `Split off` (nil)
    /// closes it.
    case split(CodeFile?)
    /// `Pane left` (0), `Pane right` (1): which pane the steps after act on.
    case pane(Int)
    /// `Peek "<text>" <file>`: the file in a box under the line with the text, as an editor peeks a definition;
    /// `Peek off` (nil) closes it.
    case peek(String?, file: CodeFile?)
    /// `Link "<a>" -> "<b>" ["<label>"]`: an arrow from one place to another, across the panes when split; `Link off`
    /// (nil) clears them all.
    case link(String?, to: String?, label: String?)
    /// `Go line 40`, `Go "func play"`: the cursor moves there, the editor scrolling to show it.
    case go(CodeAnchor)
    /// `Focus lines 20-24`: those lines bright and the rest dimmed, until `Focus off` (nil).
    case focus(ClosedRange<Int>?)
    /// `Mark "text" [n]`: a box behind the first match of the text, numbered when `n` is given; `Mark off` (nil)
    /// clears them all.
    case mark(String?, number: Int?)
    /// `Callout "text" "label"`: a bubble with the label at the first match of the text, until `Callout off` (nil).
    case callout(String?, label: String?)
    /// The director's camera over a reel of tracks (`Layout`, `Split`, `Spotlight`, `Fullscreen`, `Pip`), easing to
    /// it at render time.
    case move(Move, transition: Transition?)

    /// Drawn or edited at render time only: recording skips it, so it can change without a new take.
    public var isRenderOnly: Bool {
        switch self {
        case .caption, .speed, .hide, .move: true
        case let .zoom(target, _, _): !target.isElement
        default: false
        }
    }

    /// The elements a step names.
    var targets: [Target] {
        switch self {
        case let .click(target), let .wait(target): [target]
        case let .scroll(_, _, over): over.map { [$0] } ?? []
        case let .zoom(.element(target), _, _): [target]
        default: []
        }
    }

    public var isCaption: Bool {
        if case .caption = self { true } else { false }
    }
}

/// An element of the app, as a tape names it.
public enum Target: Equatable, Sendable, CustomStringConvertible {
    /// `"Play"` or `Play`: the element's title, description or value.
    case label(String)
    /// `#play`: the element's accessibility identifier.
    case identifier(String)
    /// `@120,80`: points from the window's top left. Not an element, so only `Click` takes it.
    case point(CGPoint)
    /// `css:.pricing`: the first visible element a CSS selector matches, on a web page.
    case css(String)

    public var description: String {
        switch self {
        case let .label(text): "\"\(text)\""
        case let .identifier(id): "#\(id)"
        case let .point(p): "@\(formatted(p.x)),\(formatted(p.y))"
        case let .css(selector): "css:\(selector)"
        }
    }

    private func formatted(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(Double(value))
    }
}

/// What a `Zoom` frames.
public enum ZoomTarget: Equatable, Sendable {
    /// Found while recording and followed while the zoom holds.
    case element(Target)
    /// Points from the window's top left.
    case point(CGPoint)
    /// Wherever the cursor is.
    case cursor
    /// Back to the whole window.
    case off

    public var isElement: Bool {
        if case .element = self { true } else { false }
    }
}

public enum ScrollDirection: String, Equatable, Sendable, CaseIterable {
    case up, down, left, right
}

public struct TapeError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// 1-based; nil for problems with the tape as a whole, such as a missing `Output`.
    public var line: Int?
    public var message: String

    public var description: String {
        line.map { "line \($0): \(message)" } ?? message
    }

    public var errorDescription: String? {
        description
    }
}

public extension Tape {
    /// Settings whose value is a list, which may have spaces in it: `Set Profiles github, social`.
    static let listSettings: Set<String> = ["Profiles", "Formats", "Redact", "Layout"]

    /// The tape read again for `profile`: its settings applied over the tape's, its Outputs named for it.
    func with(profile: Profile?, format: Output.Format? = nil) throws -> Tape {
        guard let source else { return self }
        return try Tape.parse(source.text, relativeTo: source.directory, profile: profile, format: format)
    }

    /// The profiles to render: those `chosen` on the command line, which must be among the tape's own when it names
    /// any (`Set Profiles`), or else the tape's; nil, once, when there are none, to render each Output as named.
    func profilesToRender(chosen: [String]) throws -> [Profile?] {
        for name in chosen where profile(named: name) == nil {
            throw TapeError(message: "there is no profile '\(name)'; there are \(Profile.names(known))")
        }
        if !profiles.isEmpty, let outside = chosen.first(where: { !profiles.contains($0) }) {
            throw TapeError(
                message: "the reel renders \(profiles.joined(separator: ", ")); '\(outside)' is not one of them"
            )
        }
        let names = chosen.isEmpty ? profiles : chosen
        return names.isEmpty ? [nil] : names.map { profile(named: $0) }
    }

    func profile(named name: String) -> Profile? {
        known.first { $0.name == name }
    }

    static func load(_ url: URL, asTrack: Bool = false) throws -> Tape {
        guard url.pathExtension == "reel" else {
            throw TapeError(message: "\(url.lastPathComponent) is not a reel script; those are .reel files")
        }
        return try parse(
            String(contentsOf: url, encoding: .utf8), relativeTo: url.deletingLastPathComponent(), asTrack: asTrack
        )
    }

    /// Parses a tape. Relative paths (`Output`, `Launch` of an `.app`) resolve against `directory`. With a profile,
    /// its settings apply after the tape's own.
    static func parse(
        _ text: String, relativeTo directory: URL, profile: Profile? = nil, format: Output.Format? = nil,
        asTrack: Bool = false
    ) throws -> Tape {
        // Every name a condition tests, with its line, checked once every profile is known.
        var tested: [(name: String, origin: String)] = []
        let paths = Paths(root: Paths.gitRoot(from: directory))
        var warnings: [String] = []
        // What the tape imports: applied as it Launches or Opens, when the settings can be read knowing which.
        var imported = Preset()

        var definitions: [Profile.Definition] = []
        /// `text` as a URL, from `dir`; a relative one that leads out of the git root is noted at `origin`.
        func locate(_ text: String, from dir: URL, at origin: String, fail: (String) -> TapeError) throws -> URL {
            let (url, warning) = try paths.resolve(text, against: dir, fail: fail)
            if let warning { warnings.append("\(origin): \(warning)") }
            return url
        }
        var outputs: [Output] = []
        var frameRate: Int?
        var audio: Bool?
        var size: CGSize?
        var typingSpeed: Duration?
        var waitTimeout: Duration?
        var keyBadges: Bool?
        var clickRipples: Bool?
        var gifFrameRate: Int?
        var gifWidth: Int?
        var gifColors: Int?
        var encoding = Encoding.standard
        var videoFrameRate: Int?
        var maxSize: Int?
        var maxLength: Double?
        var canvas: Output.Shape?
        var formats: Set<Output.Format>?
        var profiles: [String] = []
        var voice = VoiceSettings()
        // Each marker with its line, and whether its Say carries on (only those can be waited for).
        var markers: [String: (line: Int, over: Bool)] = [:]
        var hidden = false
        var zoomTransition = Transition.standard
        var background: Background?
        var padding = Framing.defaultPadding
        var web = WebSettings()
        var intro: Section?, outro: Section?
        var introLine = 0, outroLine = 0
        var introBackground: Background?, outroBackground: Background?
        var launch: (target: LaunchTarget, line: Int)?
        var fontSize: Int?
        var terminal = TerminalSettings()
        var scenes: [Scene] = []
        var tracks: [Track] = []
        var layout: (arrangement: Layout, origin: String)?
        /// Every track's named steps, with their lines: names are unique across a reel's tracks and its own steps.
        var trackNames: [String: Int] = [:]
        var steps: [Step] = []
        /// Each step's name, with its line.
        var named: [String: Int] = [:]

        /// One `Set`, from the tape or from its profile.
        func set(
            _ setting: String, _ value: String, isWeb: Bool, from dir: URL, at origin: String,
            fail: (String) -> TapeError
        ) throws {
            func find(_ text: String) throws -> URL {
                try locate(text, from: dir, at: origin, fail: fail)
            }
            // A preset's or a profile's value may hold a condition too; the tape's own are chosen as it is read.
            var value = value
            let tokens = value.contains("?") ? try tokenize(value, line: 0) : []
            if tokens.contains(where: { !$0.quoted && $0.text == "?" }) {
                if Profile.recordingSettings.contains(setting) || setting == "Profiles" {
                    throw fail(
                        "\(setting) cannot differ by profile: "
                            + (setting == "Profiles" ? "it chooses them" : "it is fixed when recording")
                    )
                }
                var names: [String] = []
                value = try Condition.choose(
                    tokens, profile: profile?.name, format: format, names: &names, fail: fail
                ).map(\.text).joined(separator: " ")
                tested += names.map { ($0, origin) }
            }
            let isScreen = launch?.target.isScreen == true
            let screen = launch?.target.screen
            func forWeb(_ what: String) throws {
                if !isWeb {
                    throw fail("\(what) is for web pages (Open); this reel " +
                        (screen.map { "is \($0.name)" } ?? "Launches an app"))
                }
            }
            switch setting {
            case "FrameRate":
                guard let rate = Int(value), (1 ... 120).contains(rate) else {
                    throw fail("FrameRate must be a whole number from 1 to 120, not '\(value)'")
                }
                frameRate = rate
            case "Audio":
                audio = try onOff("Audio", value, fail: fail)
            case "KeyBadges":
                keyBadges = try onOff("KeyBadges", value, fail: fail)
            case "ClickRipples":
                clickRipples = try onOff("ClickRipples", value, fail: fail)
            case "GifFrameRate":
                guard let rate = Int(value), (1 ... 50).contains(rate) else {
                    throw fail("GifFrameRate must be a whole number from 1 to 50, not '\(value)'")
                }
                gifFrameRate = rate
            case "GifWidth":
                guard let width = Int(value), (100 ... 4000).contains(width) else {
                    throw fail("GifWidth must be a whole number of pixels from 100 to 4000, not '\(value)'")
                }
                gifWidth = width
            case "GifColors":
                guard let colors = Int(value), (2 ... 256).contains(colors) else {
                    throw fail("GifColors must be a whole number from 2 to 256, not '\(value)'")
                }
                gifColors = colors
            case "Quality":
                guard let quality = Int(value), (1 ... 100).contains(quality) else {
                    throw fail("Quality must be a whole number from 1 to 100, not '\(value)'")
                }
                encoding.quality = quality
            case "Codec":
                guard let codec = Encoding.Codec(rawValue: value.lowercased()) else {
                    throw fail("Codec must be h264, hevc or prores, not '\(value)'")
                }
                encoding.codec = codec
            case "VideoWidth":
                guard let width = Int(value), (100 ... 8000).contains(width) else {
                    throw fail("VideoWidth must be a whole number of pixels from 100 to 8000, not '\(value)'")
                }
                encoding.width = width
            case "FontSize":
                guard isScreen
                else { throw fail("Set FontSize is for a code or terminal screen (Screen code, Screen terminal)") }
                guard let size = Int(value), (8 ... 72).contains(size) else {
                    throw fail("FontSize must be a whole number of points from 8 to 72, not '\(value)'")
                }
                fontSize = size
            case "VideoFrameRate":
                guard let rate = Int(value), (1 ... 120).contains(rate) else {
                    throw fail("VideoFrameRate must be a whole number from 1 to 120, not '\(value)'")
                }
                videoFrameRate = rate
            case "MaxSize":
                guard let bytes = parseBytes(value) else {
                    throw fail("MaxSize must be a size such as 10MB, 500KB or 1.5GB, not '\(value)'")
                }
                maxSize = bytes
            case "MaxLength":
                let length = try duration(value, fail: fail)
                guard length > .zero else { throw fail("MaxLength must be longer than nothing") }
                maxLength = Double(length.components.seconds) + Double(length.components.attoseconds) / 1e18
            case "Shape":
                canvas = try shape(value, fail: fail)
            case "Formats":
                let names = value.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
                var chosen = Set<Output.Format>()
                for name in names {
                    guard let format = Output.Format(rawValue: name.lowercased()) else {
                        throw fail("Formats lists mp4, mov or gif, not '\(name)'")
                    }
                    chosen.insert(format)
                }
                guard !chosen.isEmpty else { throw fail("Formats lists mp4, mov or gif") }
                formats = chosen
            case "Profiles":
                let names = value.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
                guard Set(names).count == names.count else { throw fail("Profiles names a profile twice") }
                profilesOrigin = origin
                profiles = names
            case "Browser":
                try forWeb("Set Browser")
                switch value {
                case "webkit": web.browser = .webkit
                case "chromium": web.browser = .chromium
                default:
                    let app = try find(value)
                    guard app.pathExtension == "app" else {
                        throw fail(
                            "Browser is webkit, chromium or a Chromium-based .app such as "
                                + "/Applications/Brave Browser.app, not '\(value)'"
                        )
                    }
                    web.browser = .app(app)
                }
            case "Viewport":
                // A code screen is a page too: its size in points. A terminal's is its columns and rows.
                if screen == .terminal { throw fail("a terminal screen's size is Set Columns and Set Rows") }
                if !isScreen { try forWeb("Set Viewport") }
                guard let parsed = parseSize(value) else {
                    throw fail("Viewport must be <width>x<height> in points, such as 1280x800, not '\(value)'")
                }
                web.viewport = parsed
            case "Size":
                if isWeb { throw fail("Set Size is an app's window; a web page's size is Set Viewport") }
                if screen == .code { throw fail("Set Size is an app's window; a code screen's size is Set Viewport") }
                if screen == .terminal {
                    throw fail("Set Size is an app's window; a terminal screen's size is Set Columns and Set Rows")
                }
                guard let parsed = parseSize(value) else {
                    throw fail("Size must be <width>x<height> in points, such as 1280x800, not '\(value)'")
                }
                size = parsed
            case "Voice":
                // `Set Voice <voice>` is the reel's own; `Set Voice <name> <voice>` one a `Say@<name>` speaks with.
                let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let name = parts[0]
                    guard name.first?.isLetter == true,
                          name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }), name != "over"
                    else {
                        throw fail(
                            "'\(name)' cannot name a voice; name it with letters, digits, - and _ (not over), "
                                + "such as Set Voice guest voicebox:Bella"
                        )
                    }
                    voice.named[name] = try VoiceSource(parts[1], fail: fail)
                } else {
                    voice.source = try VoiceSource(value, fail: fail)
                }
            case "VoiceServer":
                guard let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") else {
                    throw fail("VoiceServer must be an http URL, such as http://127.0.0.1:17493, not '\(value)'")
                }
                voice.server = url
            case "VoiceSeed":
                guard let seed = Int(value), seed >= 0 else {
                    throw fail("VoiceSeed must be a whole number from 0, not '\(value)'")
                }
                voice.seed = seed
            case "VoiceLanguage":
                guard value.count == 2, value.allSatisfy(\.isLowercase) else {
                    throw fail("VoiceLanguage must be a two letter code such as en or nl, not '\(value)'")
                }
                voice.language = value
            case "Ducking":
                voice.ducking = try percent("Ducking", value, fail: fail)
            case "VoiceVolume":
                voice.voiceVolume = try percent("VoiceVolume", value, fail: fail)
            case "AppVolume":
                voice.appVolume = try percent("AppVolume", value, fail: fail)
            case "Background":
                background = try Background(value, resolve: find, fail: fail)
            case "Layout":
                // A profile's settings reach its tracks too; the layout is the reel's.
                if asTrack { return }
                guard launch?.target.isTogether == true else {
                    throw fail("Set Layout arranges the tracks of a reel that records several at once (… as <name>)")
                }
                layout = try (Layout.parse(value, fail: fail), origin)
            case "Padding":
                guard value.hasSuffix("%"), let number = Double(value.dropLast()),
                      (0 ... 30).contains(number)
                else {
                    throw fail("Padding must be a percentage from 0% to 30%, not '\(value)'")
                }
                padding = number / 100
            case "IntroBackground":
                introBackground = try Background(value, resolve: find, fail: fail)
            case "OutroBackground":
                outroBackground = try Background(value, resolve: find, fail: fail)
            case "ZoomEasing":
                guard let easing = Easing(rawValue: value) else { throw fail(Easing.problem(value)) }
                zoomTransition.easing = easing
            case "ZoomDuration":
                zoomTransition.duration = try duration(value, fail: fail)
            case "Subtitles":
                voice.subtitles = try onOff("Subtitles", value, fail: fail)
            case "Columns", "Rows", "WorkingDirectory", "Theme", "Redact", "Title":
                guard screen == .terminal
                else { throw fail("Set \(setting) is for a terminal screen (Screen terminal)") }
                switch setting {
                case "Columns":
                    guard let n = Int(value), (20 ... 400).contains(n) else {
                        throw fail("Columns must be a whole number from 20 to 400, not '\(value)'")
                    }
                    terminal.columns = n
                case "Rows":
                    guard let n = Int(value), (4 ... 200).contains(n) else {
                        throw fail("Rows must be a whole number from 4 to 200, not '\(value)'")
                    }
                    terminal.rows = n
                case "WorkingDirectory":
                    terminal.workingDirectory = try find(value)
                case "Theme":
                    let url = try find(value)
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        throw fail("no theme at \(url.path)")
                    }
                    terminal.theme = url
                case "Redact":
                    try terminal.redactions.append(regex(value, fail: fail))
                default:
                    terminal.title = value
                }
            case "TypingSpeed":
                typingSpeed = try duration(value, fail: fail)
            case "WaitTimeout":
                waitTimeout = try duration(value, fail: fail)
            default:
                throw fail(
                    "unknown setting '\(setting)'; expected FrameRate, Audio, Size, TypingSpeed, WaitTimeout, "
                        + "KeyBadges, ClickRipples, Quality, Codec, VideoWidth, VideoFrameRate, MaxSize, MaxLength, Shape, "
                        + "Formats, Profiles, GifFrameRate, GifWidth, GifColors, Voice, VoiceServer, VoiceSeed, "
                        + "VoiceLanguage, Ducking, VoiceVolume, AppVolume, Subtitles, ZoomEasing, ZoomDuration, "
                        + "IntroBackground, OutroBackground, Browser, Viewport, FontSize, Columns, Rows, WorkingDirectory, Theme, "
                        + "Redact, Title, Background, Padding or Layout"
                )
            }
        }

        /// What the tape imports, applied once it says what it records (the settings are read knowing which) and
        /// before its own settings, which override them.
        func applyImports(isWeb: Bool) throws {
            for setting in imported.settings {
                let origin = setting.origin ?? "an import"
                try set(setting.name, setting.value, isWeb: isWeb, from: setting.directory ?? directory, at: origin) {
                    TapeError(message: "\(origin): \($0)")
                }
            }
        }

        let lines = Condition.joinContinuations(
            text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        )
        // Lines a Profile block took, still to skip.
        var consumed = 0
        var profilesOrigin = ""
        for (index, raw) in lines.enumerated() {
            if consumed > 0 {
                consumed -= 1
                continue
            }
            let line = index + 1
            let tokens = try tokenize(raw, line: line)
            guard let first = tokens.first else { continue }
            let fail = { (message: String) in TapeError(line: line, message: message) }
            var args = Array(tokens.dropFirst())
            // `… as <name>`: a name for the step, for other reels to wait for.
            var stepName: String?
            if args.count >= 2, !args[args.count - 2].quoted, args[args.count - 2].text == "as",
               !args[args.count - 1].quoted
            {
                let name = args[args.count - 1].text
                guard name.first?.isLetter == true,
                      name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
                else {
                    throw fail("a step's name is letters, digits, - and _, starting with a letter, not '\(name)'")
                }
                if let earlier = named[name] { throw fail("line \(earlier) is already named \(name)") }
                stepName = name
                args.removeLast(2)
            }
            let stepsBefore = steps.count
            defer {
                if let stepName, steps.count > stepsBefore { named[stepName] = line }
            }
            // A value that differs by profile: only what render decides may; what recording does is the same for all.
            if args.contains(where: { !$0.quoted && $0.text == "?" }) {
                let command = first.quoted ? first.text : split(first.text).0
                var names: [String] = []
                switch command {
                case "Set":
                    guard let setting = args.first else { throw fail("expected Set <setting> <value>") }
                    if Profile.recordingSettings.contains(setting.text) || setting.text == "Profiles" {
                        throw fail(
                            "\(setting.text) cannot differ by profile: "
                                + (setting.text == "Profiles" ? "it chooses them" : "it is fixed when recording")
                        )
                    }
                    args = try [setting] + Condition.choose(
                        Array(args.dropFirst()), profile: profile?.name, format: format, names: &names, fail: fail
                    )
                case "Caption", "Intro", "Outro", "Layout", "Spotlight", "Fullscreen", "Pip":
                    args = try Condition.choose(args, profile: profile?.name, format: format, names: &names, fail: fail)
                case "Split" where launch?.target.isTogether == true:
                    args = try Condition.choose(args, profile: profile?.name, format: format, names: &names, fail: fail)
                default:
                    throw fail(
                        "a condition (?) works in Set, Caption, Intro, Outro and the director's moves, which render "
                            + "decides; \(command) happens when recording, the same for every profile"
                    )
                }
                tested += names.map { ($0, "line \(line)") }
            }
            let words = args.map(\.text)
            let setup = { (command: String) throws in
                if !steps.isEmpty {
                    throw fail("\(command) is setup and must come before the first step (line \(steps[0].line))")
                }
            }
            let step = { (command: Command) in
                steps.append(Step(
                    line: line, source: tokens.map(\.source).joined(separator: " "), command: command, name: stepName
                ))
            }
            // `Type@20ms`: a command may carry an option after `@`; only Type takes one.
            let (name, option) = first.quoted ? (first.text, nil) : split(first.text)
            if option != nil,
               ![
                   "Type", "Say", "Zoom", "Intro", "Outro", "Output", "Include", "Code", "Diff", "Morph", "Layout",
                   "Split",
                   "Spotlight", "Fullscreen", "Pip",
               ].contains(name)
            {
                throw fail("\(name) takes no @option")
            }
            // The first line says what the tape records; everything after is read knowing it.
            if launch == nil,
               !["Launch", "Open", "Import", "Screen", "Include", "With", "Attach"].contains(name)
            {
                throw fail(Tape.preface)
            }
            let isWeb = launch?.target.isWeb == true
            let isScreen = launch?.target.isScreen == true
            let screen = launch?.target.screen
            /// What this reel is, for errors.
            let isSequence = launch?.target.isSequence == true
            let kind = screen.map { "is \($0.name)" }
                ?? (isWeb ? "Opens web pages" : isSequence ? "joins other reels" : "Launches an app")
            /// A command only some screens take.
            let forScreen = { (what: String, layouts: [ScreenLayout]) throws in
                guard let screen, layouts.contains(screen) else {
                    let names = layouts.map(\.rawValue)
                    throw fail(
                        "\(what) is for " +
                            (layouts.count == 1 ? "a \(names[0])" : "a \(names.joined(separator: " or "))")
                            + " screen: start the reel with " + names.map { "Screen \($0)" }.joined(separator: " or ")
                    )
                }
            }

            // `Screen terminal as term`, and the indented lines under it: a track, read as a reel of its own from the
            // same text, every other line blank, so what it says about a line is about the file's.
            if let stepName, ["Launch", "Open", "Screen", "Attach"].contains(name), !asTrack {
                if let earlier = launch, !earlier.target.isTogether {
                    throw fail("line \(earlier.line) says what this reel records alone; a reel of tracks names each, "
                        + "\(name) … as <name>")
                }
                var end = index + 1
                while end < lines.count, lines[end].trimmingCharacters(in: .whitespaces).isEmpty
                    || lines[end].first == " " || lines[end].first == "\t"
                {
                    end += 1
                }
                var own = lines.map { line -> String in
                    // Its imports, which come before everything, are its own too.
                    (try? tokenize(line, line: 0).first?.text) == "Import" ? line : ""
                }
                own[index] = tokens.dropLast(2).map(\.source).joined(separator: " ")
                for at in index + 1 ..< end {
                    own[at] = lines[at].trimmingCharacters(in: .whitespaces)
                }
                let read = try Tape.parse(
                    own.joined(separator: "\n"), relativeTo: directory, profile: profile, format: format, asTrack: true
                )
                try addTrack(Track(name: stepName, line: line, file: nil, tape: read))
                consumed = end - index - 1
                continue
            }
            func addTrack(_ track: Track) throws {
                if let earlier = trackNames[track.name] ?? named[track.name] {
                    throw fail("line \(earlier) is already named \(track.name)")
                }
                trackNames[track.name] = line
                for step in track.tape.steps {
                    guard let name = step.name else { continue }
                    if let earlier = trackNames[name] ?? named[name] {
                        throw TapeError(line: step.line, message: "line \(earlier) is already named \(name)")
                    }
                    trackNames[name] = step.line
                }
                tracks.append(track)
                if launch == nil {
                    launch = (.together, line)
                    try applyImports(isWeb: false)
                }
            }

            /// `<file> [lines <a>-<b>] [at line <n> | at "<text>"]`, after `command`.
            func codeFile(_ words: ArraySlice<Token>, usage command: String) throws -> CodeFile {
                let usage = "expected \(command) <file> [lines <a>-<b>] [at line <n> | at \"<text>\"]"
                guard let path = words.first, !path.quoted else { throw fail(usage) }
                var rest = words.dropFirst()
                var range: ClosedRange<Int>?
                var at: CodeAnchor?
                while let word = rest.popFirst() {
                    switch (word.quoted, word.text) {
                    case (false, "lines"):
                        guard let r = rest.popFirst().flatMap({ lineRange($0.text) }) else { throw fail(usage) }
                        range = r
                    case (false, "at"):
                        guard let next = rest.popFirst() else { throw fail(usage) }
                        at = try codeAnchor(next, rest: &rest, fail: fail)
                    default: throw fail(usage)
                    }
                }
                let url = try locate(path.text, from: directory, at: "line \(line)", fail: fail)
                return CodeFile(url: url, lines: range, at: at)
            }

            switch name {
            case "Import":
                guard launch == nil else { throw fail("Import comes first, before Launch or Open") }
                let target = try single(words, usage: "Import <path to a .\(Preset.fileExtension)>", fail: fail)
                let url = try locate(target, from: directory, at: "line \(line)", fail: fail)
                do {
                    let preset = try Preset.load(url, paths: paths, chain: [])
                    imported.settings += preset.settings
                    imported.definitions += preset.definitions
                    warnings += preset.warnings
                } catch let error as TapeError {
                    throw fail(error.message)
                }

            case "Profile":
                try setup(name)
                let (definition, used) = try Profile.Definition.read(
                    args, body: lines[(index + 1)...], from: line, in: nil, directory: directory
                )
                definitions.append(definition)
                consumed = used

            case "Intro", "Outro":
                try setup(name)
                let usage = "expected \(name) [\"<title>\" [\"<subtitle>\"]] [duration]"
                guard args.count <= 3 else { throw fail(usage) }
                // No title: the background on its own, such as a designed sting (it must be a video; checked once
                // the backgrounds are known).
                let titled = args.first?.quoted == true
                var rest = titled ? args.dropFirst() : args[...]
                let subtitle = titled && rest.first?.quoted == true ? rest.popFirst()?.text : nil
                // Untitled, all that may follow is a duration: an unquoted word is a title missing its quotes.
                if !titled, let word = rest.first, rest.count > 1 || Tape.parseDuration(word.text) == nil {
                    throw fail(usage)
                }
                let length = try rest.popFirst().map { try duration($0.text, fail: fail) }
                guard rest.isEmpty else { throw fail(usage) }
                let section = try Section(
                    title: titled ? args[0].text : "", subtitle: subtitle, duration: length,
                    transition: option.map { try SectionTransition($0, fail: fail) } ?? .standard
                )
                if name == "Intro" {
                    guard intro == nil else { throw fail("a reel has one Intro") }
                    intro = section
                    introLine = line
                } else {
                    guard outro == nil else { throw fail("a reel has one Outro") }
                    outro = section
                    outroLine = line
                }

            case "Output":
                try setup(name)
                let path = try single(words, usage: "Output <path>", fail: fail)
                let url = try locate(path, from: directory, at: "line \(line)", fail: fail)
                guard let format = Output.Format(rawValue: url.pathExtension.lowercased()) else {
                    let known = Output.Format.allCases.map { ".\($0.rawValue)" }
                    let list = known.dropLast().joined(separator: ", ") + " or " + known.last!
                    throw fail("unsupported output type '.\(url.pathExtension)'; expected \(list)")
                }
                if outputs.contains(where: { $0.url == url }) {
                    throw fail("\(path) is already an Output")
                }
                try outputs.append(Output(url: url, format: format, shape: option.map { try shape($0, fail: fail) }))

            case "Set":
                try setup(name)
                if isSequence, let setting = words.first, Profile.recordingSettings.contains(setting) {
                    throw fail("Set \(setting) is fixed when a scene is recorded: set it in the scene's reel")
                }
                guard words.count == 2 || (words.count > 2 && Tape.listSettings.contains(words[0]))
                    || (words.count == 3 && words[0] == "Voice")
                else {
                    throw fail("expected Set <setting> <value>")
                }
                try set(
                    words[0], words.dropFirst().joined(separator: " "), isWeb: isWeb, from: directory,
                    at: "line \(line)", fail: fail
                )

            case "Open":
                let value = try single(words, usage: "Open <url>", fail: fail)
                let url = try webAddress(value, resolve: {
                    try locate($0, from: directory, at: "line \(line)", fail: fail)
                }, fail: fail)
                if launch == nil {
                    launch = (.web(url), line)
                    try applyImports(isWeb: true)
                } else {
                    // Any later Open goes to another page, as a step.
                    guard isWeb else { throw fail("Open goes to a web page; this reel \(kind)") }
                    step(.open(url))
                }

            case "Attach":
                try setup(name)
                guard asTrack else {
                    throw fail("Attach records an app something else opens, as a track: Attach <app> as <name>")
                }
                let target = try single(words, usage: "Attach <bundle id or .app path> as <name>", fail: fail)
                launch = try (
                    .attach(target.contains("/")
                        ? locate(target, from: directory, at: "line \(line)", fail: fail).path : target),
                    line
                )
                try applyImports(isWeb: false)

            case "Launch":
                try setup(name)
                let target = try single(words, usage: "Launch <bundle id or .app path>", fail: fail)
                if let earlier = launch {
                    throw fail(
                        isWeb ? "a web reel Opens pages; line \(earlier.line) already does, so there is no app to Launch"
                            : screen
                            .map { "this reel is \($0.name) (line \(earlier.line)), so there is no app to Launch" }
                            ?? (
                                isSequence ? "this reel joins other reels (line \(earlier.line)); Launch the app in one of them"
                                    : "a reel launches one app; line \(earlier.line) already does"
                            )
                    )
                }
                // A path has a slash (`./Name.app` beside the tape); anything else is a bundle id, which may itself end
                // in `.app` (`dev.musicbox.app`).
                let isPath = target.contains("/")
                launch = try (
                    isPath ? .app(locate(target, from: directory, at: "line \(line)", fail: fail)) : .bundleID(target),
                    line
                )
                try applyImports(isWeb: false)

            case "With":
                try setup(name)
                guard !asTrack
                else { throw fail("a track records one subject; With belongs in the reel that joins them") }
                guard let stepName else { throw fail("expected With <track.reel> as <name>") }
                if let earlier = launch, !earlier.target.isTogether {
                    throw fail("With adds a track to a reel of tracks; this reel \(kind) (line \(earlier.line))")
                }
                let path = try single(words, usage: "With <track.reel> as <name>", fail: fail)
                let url = try locate(path, from: directory, at: "line \(line)", fail: fail)
                guard FileManager.default.fileExists(atPath: url.path) else { throw fail("no reel at \(url.path)") }
                let read: Tape
                do {
                    read = try Tape.load(url, asTrack: true)
                } catch let error as TapeError {
                    throw fail("\(url.lastPathComponent)\(error.line.map { " line \($0)" } ?? ""): \(error.message)")
                }
                try addTrack(Track(name: stepName, line: line, file: url, tape: read))
                continue

            case "Include":
                try setup(name)
                if let earlier = launch, !isSequence {
                    throw fail("Include joins other reels; this reel \(kind) (line \(earlier.line))")
                }
                let path = try single(words, usage: "Include[@<transition>] <scene.reel>", fail: fail)
                let url = try locate(path, from: directory, at: "line \(line)", fail: fail)
                guard url.pathExtension == "reel"
                else { throw fail("Include takes a .reel, not \(url.lastPathComponent)") }
                guard FileManager.default.fileExists(atPath: url.path) else { throw fail("no reel at \(url.path)") }
                if scenes.isEmpty, option != nil {
                    throw fail(
                        "the first scene has nothing before it to move from; give the transition on the next Include"
                    )
                }
                let transition = try option.map { try SectionTransition($0, fail: fail) }
                scenes.append(Scene(url: url, transition: scenes.isEmpty ? nil : transition ?? .standard))
                if launch == nil {
                    launch = (.sequence, line)
                    try applyImports(isWeb: false)
                }

            case "Screen":
                try setup(name)
                if let earlier = launch {
                    throw fail("line \(earlier.line) already says what this reel records; a reel records one thing")
                }
                let usage = "expected Screen code or Screen terminal"
                guard let layout = try ScreenLayout(rawValue: single(words, usage: usage, fail: fail)) else {
                    throw fail(usage)
                }
                launch = (.screen(layout), line)
                try applyImports(isWeb: false)

            case "Code":
                try forScreen("Code", [.code])
                let file = try codeFile(args[...], usage: "Code[@<transition>]")
                try step(.code(file, transition: option.map { try SectionTransition($0, fail: fail) }))

            case "Diff":
                try forScreen("Diff", [.code])
                let usage = "expected Diff[@<transition>] <before> <after> or Diff[@<transition>] <file> since <revision>, "
                    + "then [at line <n> | at hunk <n> | at \"<text>\"]"
                var rest = args[...]
                guard let first = rest.popFirst(), !first.quoted, let second = rest.popFirst(), !second.quoted else {
                    throw fail(usage)
                }
                let after: URL
                let before: DiffSource.Before
                if second.text == "since" {
                    guard let revision = rest.popFirst(), !revision.text.isEmpty else { throw fail(usage) }
                    after = try locate(first.text, from: directory, at: "line \(line)", fail: fail)
                    before = .revision(revision.text)
                } else {
                    before = try .file(locate(first.text, from: directory, at: "line \(line)", fail: fail))
                    after = try locate(second.text, from: directory, at: "line \(line)", fail: fail)
                }
                var at: CodeAnchor?
                if let word = rest.popFirst() {
                    guard !word.quoted, word.text == "at", let next = rest.popFirst() else { throw fail(usage) }
                    at = try codeAnchor(next, rest: &rest, fail: fail)
                }
                guard rest.isEmpty else { throw fail(usage) }
                try step(.diff(
                    DiffSource(before: before, after: after, at: at),
                    transition: option.map { try SectionTransition($0, fail: fail) }
                ))

            case "Follow":
                try forScreen("Follow", [.code])
                guard words.isEmpty || words == ["off"] else { throw fail("expected Follow or Follow off") }
                step(.follow(words.isEmpty))

            case "Morph":
                try forScreen("Morph", [.code])
                let file = try codeFile(args[...], usage: "Morph[@<easing>,<duration>]")
                try step(.morph(file, motion: option.map { try Transition($0, fail: fail) }))

            case "Split" where launch?.target.isTogether == true:
                let transition = try option.map { try Transition($0, fail: fail) }
                if words == ["off"] {
                    step(.move(.split(nil), transition: transition))
                } else {
                    let shares = try words.map { word -> Double in
                        guard word.hasSuffix("%"), let value = Double(word.dropLast()), value > 0, value < 100 else {
                            throw fail("expected Split <share>% …, such as Split 40%, or Split off")
                        }
                        return value / 100
                    }
                    guard !shares.isEmpty
                    else { throw fail("expected Split <share>% …, such as Split 40%, or Split off") }
                    let total = shares.reduce(0, +)
                    guard total <= 1.0001 else {
                        throw fail("the shares add up to \(Layout.percent(total)); they make at most 100%")
                    }
                    step(.move(.split(shares), transition: transition))
                }

            case "Layout", "Spotlight", "Fullscreen", "Pip":
                guard launch?.target.isTogether == true else {
                    throw fail("\(name) directs the tracks of a reel that records several at once (… as <name>)")
                }
                let transition = try option.map { try Transition($0, fail: fail) }
                let move: Move
                switch name {
                case "Layout":
                    guard !args.isEmpty else { throw fail("expected Layout <arrangement>; \(Layout.usage)") }
                    move = try .layout(Layout.parse(args.map(\.source).joined(separator: " "), fail: fail))
                case "Spotlight", "Fullscreen":
                    guard words.count == 1,
                          !args[0].quoted else { throw fail("expected \(name) <track> or \(name) off") }
                    let track = words[0] == "off" ? nil : words[0]
                    move = name == "Spotlight" ? .spotlight(track) : .fullscreen(track)
                default:
                    let usage = "expected Pip <track> [over <track>] [top-left|top-right|bottom-left|bottom-right] "
                        + "or Pip off"
                    if words == ["off"] {
                        move = .pip(nil)
                        break
                    }
                    guard let first = words.first, !args.contains(where: \.quoted) else { throw fail(usage) }
                    var pip = Pip(name: first, over: nil, corner: .bottomRight)
                    var rest = words.dropFirst()
                    if rest.first == "over" {
                        rest.removeFirst()
                        guard let over = rest.popFirst() else { throw fail(usage) }
                        guard over != first
                        else { throw fail("a picture-in-picture is over another track, not itself") }
                        pip.over = over
                    }
                    if let corner = rest.popFirst() {
                        guard let value = Pip.Corner(rawValue: corner) else {
                            throw fail("'\(corner)' is not a corner; expected "
                                + Pip.Corner.allCases.map(\.rawValue).joined(separator: ", "))
                        }
                        pip.corner = value
                    }
                    guard rest.isEmpty else { throw fail(usage) }
                    move = .pip(pip)
                }
                step(.move(move, transition: transition))

            case "Split":
                try forScreen("Split", [.code])
                if words == ["off"] {
                    step(.split(nil))
                } else {
                    try step(.split(codeFile(args[...], usage: "Split")))
                }

            case "Pane":
                try forScreen("Pane", [.code])
                guard words.count == 1, let side = ["left", "right"].firstIndex(of: words[0]) else {
                    throw fail("expected Pane left or Pane right")
                }
                step(.pane(side))

            case "Peek":
                try forScreen("Peek", [.code])
                if args.count == 1, !args[0].quoted, args[0].text == "off" {
                    step(.peek(nil, file: nil))
                } else {
                    guard let first = args.first, first.quoted, !first.text.isEmpty else {
                        throw fail(
                            "expected Peek \"<text>\" <file> [lines <a>-<b>] [at line <n> | at \"<text>\"] or Peek off"
                        )
                    }
                    try step(.peek(first.text, file: codeFile(args.dropFirst(), usage: "Peek \"<text>\"")))
                }

            case "Link":
                try forScreen("Link", [.code])
                if args.count == 1, !args[0].quoted, args[0].text == "off" {
                    step(.link(nil, to: nil, label: nil))
                } else {
                    guard (3 ... 4).contains(args.count), args[0].quoted, !args[1].quoted, args[1].text == "->",
                          args[2].quoted, args.dropFirst(3).allSatisfy(\.quoted), !args[0].text.isEmpty,
                          !args[2].text.isEmpty
                    else {
                        throw fail("expected Link \"<text>\" -> \"<text>\" [\"<label>\"] or Link off")
                    }
                    step(.link(args[0].text, to: args[2].text, label: args.count == 4 ? args[3].text : nil))
                }

            case "Go":
                try forScreen("Go", [.code])
                let usage = "expected Go line <n>, Go hunk <n> or Go \"<text>\""
                guard let first = args.first else { throw fail(usage) }
                var rest = args.dropFirst()
                let anchor = try codeAnchor(first, rest: &rest, fail: fail)
                guard rest.isEmpty else { throw fail(usage) }
                step(.go(anchor))

            case "Focus":
                try forScreen("Focus", [.code])
                if words == ["off"] {
                    step(.focus(nil))
                } else {
                    guard words.count == 2, words[0] == "lines", let range = lineRange(words[1]) else {
                        throw fail("expected Focus lines <a>-<b> or Focus off")
                    }
                    step(.focus(range))
                }

            case "Mark":
                try forScreen("Mark", [.code, .terminal])
                if args.count == 1, !args[0].quoted, args[0].text == "off" {
                    step(.mark(nil, number: nil))
                } else {
                    let usage = "expected Mark \"<text>\" [number] or Mark off"
                    guard (1 ... 2).contains(args.count), args[0].quoted,
                          !args[0].text.isEmpty else { throw fail(usage) }
                    let number = try args.dropFirst().first.map { word -> Int in
                        guard !word.quoted, let n = Int(word.text), (1 ... 99).contains(n) else {
                            throw fail("a mark's number is 1 to 99, not '\(word.text)'")
                        }
                        return n
                    }
                    step(.mark(args[0].text, number: number))
                }

            case "Callout":
                try forScreen("Callout", [.code, .terminal])
                if args.count == 1, !args[0].quoted, args[0].text == "off" {
                    step(.callout(nil, label: nil))
                } else {
                    guard args.count == 2, args[0].quoted, args[1].quoted, !args[0].text.isEmpty else {
                        throw fail("expected Callout \"<text>\" \"<label>\" or Callout off")
                    }
                    step(.callout(args[0].text, label: args[1].text))
                }

            case "Sleep":
                let value = try single(words, usage: "Sleep <duration>", fail: fail)
                try step(.sleep(duration(value, fail: fail)))

            case "Click":
                guard args.count == 1
                else { throw fail("expected Click \"<label>\", Click #<identifier> or Click @x,y") }
                try step(.click(target(args[0], fail: fail)))

            case "Wait" where words.first == "for":
                guard words.count == 2 || (words.count == 4 && words[2] == "to" && words[3] == "end"),
                      !args[1].quoted
                else {
                    throw fail("expected Wait for <name> or Wait for <name> to end")
                }
                step(.waitFor(words[1], end: words.count == 4))

            case "Wait" where screen == .terminal && !(words.first?.hasPrefix("[") ?? false):
                let usage = "expected Wait /<regex>/, Wait quiet [duration], Wait exit or Wait [marker]"
                switch words.first {
                case "exit":
                    guard words.count == 1 else { throw fail(usage) }
                    step(.expect(.exit))
                case "quiet":
                    guard words.count <= 2 else { throw fail(usage) }
                    try step(.expect(.quiet(words.count == 2 ? duration(words[1], fail: fail) : Tape.defaultQuiet)))
                case let first? where first.hasPrefix("/") && !args[0].quoted:
                    // A pattern may hold spaces: the words between the slashes, as written.
                    try step(.expect(.output(regex(words.joined(separator: " "), fail: fail))))
                default:
                    throw fail(usage)
                }

            case "Wait":
                guard args.count == 1
                else { throw fail("expected Wait \"<label>\", Wait #<identifier> or Wait [marker]") }
                if !args[0].quoted, args[0].text.hasPrefix("["), args[0].text.hasSuffix("]") {
                    let name = String(args[0].text.dropFirst().dropLast())
                    guard let marker = markers[name] else {
                        throw fail("no Say before this has a marker [\(name)]")
                    }
                    guard marker.over else {
                        throw fail(
                            "the Say on line \(marker.line) waits until it ends, so [\(name)] has passed by now; "
                                + "write Say@over to act while it speaks"
                        )
                    }
                    step(.reach(name))
                    continue
                }
                let target = try target(args[0], fail: fail)
                if case .point = target { throw fail("Wait needs an element to wait for, not a point") }
                step(.wait(target))

            case "Type":
                let text = try single(words, usage: "Type \"<text>\"", fail: fail)
                try step(.type(text, pause: option.map { try duration($0, fail: fail) }))

            case "Key":
                guard (1 ... 2).contains(words.count) else { throw fail("expected Key <combo> [count]") }
                guard let combo = KeyCombo(words[0]) else {
                    throw fail(
                        "'\(words[0])' is not a key; write a key name such as return or a, with modifiers: cmd+s"
                    )
                }
                try step(.key(combo, count: count(words.dropFirst().first, fail: fail)))

            case "Scroll":
                let usage = "expected Scroll <up|down|left|right> [lines] [element or @x,y]"
                guard (1 ... 3).contains(args.count) else { throw fail(usage) }
                guard let direction = ScrollDirection(rawValue: words[0]) else {
                    throw fail("'\(words[0])' is not a direction; expected up, down, left or right")
                }
                // A number after the direction is the lines; whatever follows is what to scroll over.
                var rest = args.dropFirst()
                let lines = if let next = rest.first, !next.quoted, next.text.first?.isNumber == true {
                    try count(rest.popFirst()?.text, fail: fail)
                } else {
                    1
                }
                guard rest.count <= 1 else { throw fail(usage) }
                try step(.scroll(direction, lines: lines, over: rest.first.map { try target($0, fail: fail) }))

            case "Zoom":
                let usage = "expected Zoom <element or @x,y> [scale], Zoom cursor [scale] or Zoom off"
                guard (1 ... 2).contains(args.count) else { throw fail(usage) }
                let scale = try args.dropFirst().first.map { try zoomScale($0.text, fail: fail) }
                let transition = try option.map { try Transition($0, fail: fail) }
                switch (args[0].quoted, args[0].text) {
                case (false, "off"):
                    guard scale == nil else { throw fail("Zoom off takes no scale") }
                    step(.zoom(.off, scale: nil, transition: transition))
                case (false, "cursor"):
                    step(.zoom(.cursor, scale: scale, transition: transition))
                default:
                    switch try target(args[0], fail: fail) {
                    case let .point(p): step(.zoom(.point(p), scale: scale, transition: transition))
                    case let element:
                        // Recording only finds the element: its timeline names that alone, so the scale and the
                        // easing can change without a new take.
                        steps.append(Step(
                            line: line, source: "Zoom \(args[0].source)",
                            command: .zoom(.element(element), scale: scale, transition: transition)
                        ))
                    }
                }

            case "Speed":
                guard args.count == 1 else { throw fail("expected Speed <rate>x or Speed off") }
                if words[0] == "off" {
                    step(.speed(nil))
                } else {
                    guard words[0].hasSuffix("x"), let rate = Double(words[0].dropLast()), rate > 1, rate <= 16 else {
                        throw fail("Speed must be a rate above 1x and up to 16x, such as 4x, not '\(words[0])'")
                    }
                    step(.speed(rate))
                }

            case "Hide", "Show":
                guard args.isEmpty else { throw fail("\(name) takes nothing") }
                if (name == "Hide") == hidden {
                    throw fail(name == "Hide" ? "already hidden; Show comes first" : "nothing is hidden to Show")
                }
                hidden = name == "Hide"
                step(.hide(hidden))

            case "Say":
                // `Say@over`, `Say@guest` (a voice named with Set Voice), or both: `Say@guest,over`.
                let options = option.map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
                    ?? []
                let over = options.contains("over")
                let named = options.filter { $0 != "over" }
                guard named.count <= 1, options.count == Set(options).count, !named.contains("") else {
                    throw fail("Say takes @over, a voice's name, or both (Say@guest,over), not @\(option!)")
                }
                if let name = named.first, voice.named[name] == nil {
                    throw fail("no voice is named \(name); name one first with Set Voice \(name) <voice>")
                }
                let text = try single(words, usage: "Say \"<text>\"", fail: fail)
                let speech = try Speech(text, voice: named.first, fail: fail)
                for name in speech.markers {
                    if let earlier = markers[name] {
                        throw fail("[\(name)] is already a marker on line \(earlier.line)")
                    }
                    markers[name] = (line, over)
                }
                step(.say(speech, over: over))

            case "Caption":
                // `Caption "text" [duration]`, or `Caption off`; a quoted "off" is text.
                guard (1 ... 2).contains(args.count)
                else { throw fail("expected Caption \"<text>\" [duration] or Caption off") }
                if !args[0].quoted, args[0].text == "off" {
                    guard args.count == 1 else { throw fail("Caption off takes no duration") }
                    step(.caption(nil, duration: nil))
                } else {
                    try step(.caption(
                        args[0].text,
                        duration: args.dropFirst().first.map { try duration($0.text, fail: fail) }
                    ))
                }

            default:
                let known = [
                    "Output", "Set", "Launch", "Sleep", "Click", "Wait", "Type", "Key", "Scroll", "Caption", "Say",
                    "Zoom", "Speed", "Hide", "Show", "Intro", "Outro", "Open", "Screen", "Code", "Go", "Focus", "Mark",
                    "Callout", "Include", "Split", "Pane", "Peek", "Link", "Diff", "Morph", "With", "Follow", "Attach",
                    "Layout", "Spotlight", "Fullscreen", "Pip",
                ]
                let hint = known.first { $0.lowercased() == name.lowercased() }.map { "; did you mean \($0)?" }
                throw fail("unknown command '\(name)'" + (hint ?? "; expected one of \(known.joined(separator: ", "))"))
            }
            if let stepName, steps.count == stepsBefore {
                throw fail(
                    "as names a step, for other reels to wait for; \(name) is not a step, so it cannot be \(stepName)"
                )
            }
        }

        guard let launch else { throw TapeError(message: Tape.preface) }
        // Its own steps run in order: by a Wait for one of them, it has passed, or it will never come.
        for step in steps {
            if case let .waitFor(name, _) = step.command, let own = named[name] {
                throw TapeError(
                    line: step.line,
                    message: "\(name) is this reel's own step (line \(own)); Wait for waits for a step of another reel"
                )
            }
        }
        if launch.target.isTogether {
            // The director's steps: what is said and shown over every track, and when.
            for step in steps {
                switch step.command {
                case .say, .caption, .sleep, .waitFor, .reach, .speed, .hide: continue
                case let .move(move, _):
                    for name in move.names where !tracks.contains(where: { $0.name == name }) {
                        throw TapeError(line: step.line, message: Tape.noTrack(name, in: tracks))
                    }
                    if case let .layout(arrangement) = move, let twice = Tape.twice(arrangement) {
                        throw TapeError(line: step.line, message: "\(twice) is in the layout twice")
                    }
                    continue
                default:
                    let command = step.source.split(separator: " ").first.map(String.init) ?? "it"
                    throw TapeError(
                        line: step.line,
                        message: "\(command) acts on a subject: indent it under the track it belongs to"
                    )
                }
            }
        }
        // A track has no Outputs of its own: the reel that joins it writes them.
        guard asTrack || !outputs.isEmpty else { throw TapeError(message: "the reel has no Output") }
        for (name, section, background, line) in [
            ("Intro", intro, introBackground ?? intro?.background, introLine),
            ("Outro", outro, outroBackground ?? outro?.background, outroLine),
        ] {
            guard let section, section.title.isEmpty else { continue }
            if case .video = background { continue }
            throw TapeError(
                line: line,
                message: "an \(name) without a title shows its background on its own, so that must be a video: "
                    + "Set \(name)Background <video>"
            )
        }
        let knownProfiles = try Profile.resolve(imported.definitions + definitions)
        for (name, origin) in tested
            where !Condition.formats.contains(name) && !knownProfiles.contains(where: { $0.name == name })
        {
            throw TapeError(
                message: "\(origin): there is no profile '\(name)' to test; there are "
                    + "\(Profile.names(knownProfiles)), and an Output's type: mp4, mov or gif"
            )
        }
        for name in profiles where !knownProfiles.contains(where: { $0.name == name }) {
            throw TapeError(
                message: "\(profilesOrigin): there is no profile '\(name)'; there are \(Profile.names(knownProfiles))"
            )
        }
        if let profile {
            for setting in profile.settings {
                let origin = setting.origin.map { " (\($0))" } ?? ""
                try set(
                    setting.name, setting.value, isWeb: launch.target.isWeb, from: setting.directory ?? directory,
                    at: setting.origin ?? "profile \(profile.name)"
                ) { TapeError(message: "profile \(profile.name)\(origin): \($0)") }
            }
        }
        // `Set Shape` frames every Output that names no shape of its own; `Set Formats` leaves out the others; a
        // profile's Outputs carry its name.
        var skipped: [Output] = []
        outputs = outputs.compactMap { output in
            var output = output
            if let formats, !formats.contains(output.format) {
                skipped.append(output)
                return nil
            }
            // Read for one type, the tape writes only Outputs of it.
            if let format, output.format != format { return nil }
            output.shape = output.shape ?? canvas
            if let profile { output.url = profile.suffixed(output.url) }
            return output
        }
        if launch.target.isSequence, let first = steps.first {
            throw TapeError(
                line: first.line, message: "a reel of scenes has no steps of its own: they belong in its scenes' reels"
            )
        }
        if launch.target.isScreen {
            for step in steps {
                if let problem = screenProblem(step.command, on: launch.target.screen ?? .code) {
                    throw TapeError(line: step.line, message: problem)
                }
            }
        }
        if !launch.target.isWeb {
            for step in steps
                where step.command.targets.contains(where: { if case .css = $0 { true } else { false } })
            {
                throw TapeError(line: step.line, message: "css: targets are for web pages; Open one instead of Launch")
            }
        }

        if let layout {
            for name in layout.arrangement.names where !tracks.contains(where: { $0.name == name }) {
                throw TapeError(message: "\(layout.origin): \(Tape.noTrack(name, in: tracks))")
            }
            if let twice = Tape.twice(layout.arrangement) {
                throw TapeError(message: "\(layout.origin): \(twice) is in the layout twice")
            }
        }

        return Tape(
            outputs: outputs,
            frameRate: frameRate ?? defaultFrameRate,
            audio: audio ?? true,
            size: size,
            typingSpeed: typingSpeed ?? defaultTypingSpeed,
            waitTimeout: waitTimeout ?? defaultWaitTimeout,
            keyBadges: keyBadges ?? true,
            clickRipples: clickRipples ?? true,
            gifFrameRate: gifFrameRate ?? defaultGifFrameRate,
            gifWidth: gifWidth ?? defaultGifWidth,
            gifColors: gifColors ?? defaultGifColors,
            encoding: encoding,
            videoFrameRate: videoFrameRate,
            maxSize: maxSize,
            maxLength: maxLength,
            profiles: profiles,
            profile: profile,
            skipped: skipped,
            source: Source(text: text, directory: directory),
            known: knownProfiles,
            warnings: warnings,
            conditionsOnFormat: tested.contains { Condition.formats.contains($0.name) },
            voice: voice,
            zoomTransition: zoomTransition,
            intro: intro.map { section in
                var section = section
                section.background = introBackground ?? section.background
                return section
            },
            outro: outro.map { section in
                var section = section
                section.background = outroBackground ?? section.background
                return section
            },
            web: web,
            terminal: {
                // The shell starts beside the reel unless it says otherwise.
                var terminal = terminal
                terminal.workingDirectory = terminal.workingDirectory ?? directory
                return terminal
            }(),
            scenes: scenes,
            tracks: tracks,
            fontSize: fontSize ?? defaultFontSize,
            background: background,
            padding: padding,
            launch: launch.target,
            steps: steps,
            layout: layout?.arrangement
        )
    }

    /// `500ms`, `2s`, `1.5s`, `1m`, or a bare number of seconds.
    static func parseDuration(_ text: String) -> Duration? {
        let units: [(suffix: String, seconds: Double)] = [("ms", 0.001), ("s", 1), ("m", 60)]
        let (number, scale) = units.first { text.hasSuffix($0.suffix) }
            .map { (String(text.dropLast($0.suffix.count)), $0.seconds) } ?? (text, 1)
        guard let value = Double(number), value >= 0, value.isFinite, number.first?.isNumber == true else {
            return nil
        }
        return .milliseconds(Int64((value * scale * 1000).rounded()))
    }
}

private func duration(_ text: String, fail: (String) -> TapeError) throws -> Duration {
    guard let duration = Tape.parseDuration(text) else {
        throw fail("'\(text)' is not a duration; write 500ms, 2s, 1.5s or a number of seconds")
    }
    return duration
}

/// `2x`, `1.5x`: from 1 to 8.
private func zoomScale(_ text: String, fail: (String) -> TapeError) throws -> Double {
    guard text.hasSuffix("x"), let scale = Double(text.dropLast()), scale >= 1, scale <= 8 else {
        throw fail("a zoom scale is 1x to 8x, such as 2x, not '\(text)'")
    }
    return scale
}

/// `25%`: a fraction from 0 to 1.
private func percent(_ setting: String, _ value: String, fail: (String) -> TapeError) throws -> Double {
    guard value.hasSuffix("%"), let number = Double(value.dropLast()), (0 ... 100).contains(number) else {
        throw fail("\(setting) must be a percentage from 0% to 100%, not '\(value)'")
    }
    return number / 100
}

private func onOff(_ setting: String, _ value: String, fail: (String) -> TapeError) throws -> Bool {
    switch value {
    case "on": return true
    case "off": return false
    default: throw fail("\(setting) must be on or off, not '\(value)'")
    }
}

private func count(_ text: String?, fail: (String) -> TapeError) throws -> Int {
    guard let text else { return 1 }
    guard let count = Int(text), (1 ... 100).contains(count) else {
        throw fail("the count must be a whole number from 1 to 100, not '\(text)'")
    }
    return count
}

/// A quoted word is always a label; unquoted, `#` starts an identifier and `@` a point.
private func target(_ token: Token, fail: (String) -> TapeError) throws -> Target {
    let text = token.text
    // `css:"form button"`: a selector with spaces is quoted after the colon. A word that starts with a quote is a
    // label, whatever it says.
    if text.hasPrefix("css:"), !token.source.hasPrefix("\"") {
        guard text.count > 4 else { throw fail("css: needs a selector after it, such as css:.pricing") }
        return .css(String(text.dropFirst(4)))
    }
    if token.quoted { return .label(text) }
    // A `#` on its own is a comment, so an unquoted `#` here always has an identifier after it.
    if text.hasPrefix("#") { return .identifier(String(text.dropFirst())) }
    if text.hasPrefix("@") {
        let parts = text.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]), x >= 0, y >= 0 else {
            throw fail("'\(text)' is not a point; write @x,y in points from the window's top left, such as @120,80")
        }
        return .point(CGPoint(x: x, y: y))
    }
    return .label(text)
}

/// `https://…`, `http://…`, `file://…`, or a path to an `.html` file relative to the tape.
private func webAddress(
    _ value: String, resolve: (String) throws -> URL, fail: (String) -> TapeError
) throws -> URL {
    if let url = URL(string: value), let scheme = url.scheme, ["http", "https", "file"].contains(scheme) {
        return url
    }
    if value.hasSuffix(".html") || value.hasSuffix(".htm") { return try resolve(value) }
    throw fail("'\(value)' is not a web address; write https://…, http://…, file://… or a path to an .html file")
}

/// `16:9`, `1:1`, `9:16`, or an exact `1080x1080` in pixels.
private func shape(_ text: String, fail: (String) -> TapeError) throws -> Output.Shape {
    let problem = "'@\(text)' is not a shape; write an aspect such as @16:9, @1:1 or @9:16, or a size such as @1080x1080"
    if text.contains(":") {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), (1 ... 100).contains(w),
              (1 ... 100).contains(h)
        else { throw fail(problem) }
        return .aspect(w, h)
    }
    let parts = text.split(separator: "x", omittingEmptySubsequences: false)
    guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), (64 ... 8192).contains(w),
          (64 ... 8192).contains(h)
    else { throw fail(problem) }
    return .size(w, h)
}

/// `10MB`, `500KB`, `1.5GB`: decimal units, as the sites that set limits count them.
func parseBytes(_ text: String) -> Int? {
    let units: [(suffix: String, bytes: Double)] = [("KB", 1e3), ("MB", 1e6), ("GB", 1e9)]
    guard let unit = units.first(where: { text.uppercased().hasSuffix($0.suffix) }),
          let number = Double(text.dropLast(2)), number > 0, number.isFinite
    else { return nil }
    return Int(number * unit.bytes)
}

private func parseSize(_ text: String) -> CGSize? {
    let parts = text.split(separator: "x", omittingEmptySubsequences: false)
    guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]),
          (100 ... 8000).contains(width), (100 ... 8000).contains(height)
    else { return nil }
    return CGSize(width: width, height: height)
}

private func split(_ command: String) -> (String, String?) {
    guard let at = command.firstIndex(of: "@") else { return (command, nil) }
    return (String(command[..<at]), String(command[command.index(after: at)...]))
}

private func single(_ args: [String], usage: String, fail: (String) -> TapeError) throws -> String {
    guard args.count == 1 else { throw fail("expected \(usage)") }
    return args[0]
}

func resolve(_ path: String, against directory: URL) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    // Appended rather than `relativeTo:`, which resolves against the parent of a directory URL without a slash.
    let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : directory.appending(path: expanded)
    return url.standardizedFileURL
}

struct Token {
    var text: String
    var quoted: Bool
    /// As written, quotes and all, for the timeline.
    var source: String
}

extension Tape {
    /// The error for a move or a layout that names a track the reel has not.
    static func noTrack(_ name: String, in tracks: [Track]) -> String {
        "there is no track \(name); the tracks are " + tracks.map(\.name).joined(separator: ", ")
    }

    /// The first track an arrangement names more than once.
    static func twice(_ arrangement: Layout) -> String? {
        var seen = Set<String>()
        return arrangement.names.first { !seen.insert($0).inserted }
    }
}

/// Splits a line into tokens: whitespace separates, double quotes group (`\"` and `\\` escape inside them). `#`
/// starts a comment at the start of a line or followed by a space; `#play` after a command is an identifier.
func tokenize(_ line: String, line number: Int) throws -> [Token] {
    var tokens: [Token] = []
    var current = "", source = ""
    var inToken = false, quoted = false, wasQuoted = false
    var chars = Array(line)[...]
    func flush() {
        if inToken { tokens.append(Token(text: current, quoted: wasQuoted, source: source)) }
        current = ""
        source = ""
        inToken = false
        wasQuoted = false
    }
    while let c = chars.popFirst() {
        if quoted {
            source.append(c)
            switch c {
            case "\"": quoted = false
            case "\\":
                guard let next = chars.popFirst() else { break }
                source.append(next)
                switch next {
                case "n": current.append("\n")
                case "t": current.append("\t")
                default: current.append(next)
                }
            default: current.append(c)
            }
        } else if c == "\"" {
            source.append(c)
            quoted = true
            wasQuoted = true
            inToken = true
        } else if c == "#", !inToken, tokens.isEmpty || chars.first?.isWhitespace != false {
            break
        } else if c.isWhitespace {
            flush()
        } else {
            source.append(c)
            current.append(c)
            inToken = true
        }
    }
    if quoted { throw TapeError(line: number, message: "unterminated quote") }
    flush()
    return tokens
}

/// `12-40`, or a single line `12`.
private func lineRange(_ text: String) -> ClosedRange<Int>? {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard (1 ... 2).contains(parts.count), let a = Int(parts[0]), let b = Int(parts[parts.count - 1]), a >= 1, b >= a
    else { return nil }
    return a ... b
}

/// `line 40` (the number taken from `rest`), or `"text"`.
private func codeAnchor(
    _ word: Token, rest: inout ArraySlice<Token>, fail: (String) -> TapeError
) throws -> CodeAnchor {
    if word.quoted {
        guard !word.text.isEmpty else {
            throw fail("a place in the code is line <n>, hunk <n> or some text to find, in quotes")
        }
        return .text(word.text)
    }
    guard ["line", "hunk"].contains(word.text), let n = rest.popFirst().flatMap({ Int($0.text) }), n >= 1 else {
        throw fail("a place in the code is line <n>, hunk <n> or some text to find, in quotes")
    }
    return word.text == "line" ? .line(n) : .hunk(n)
}

/// Why a step cannot be on a screen, nil when it can. The screen is reel's own: there is nothing to click, scroll or
/// find, and it takes only the keys its editor or terminal does.
private func screenProblem(_ command: Command, on screen: ScreenLayout) -> String? {
    switch (command, screen) {
    case (.click, .code), (.scroll, .code), (.open, .code):
        "a code screen has no app or page to drive; it takes Code, Go, Type, Key and the rest"
    case (.click, .terminal), (.scroll, .terminal), (.open, .terminal):
        "a terminal screen has no app or page to drive; it takes Type, Key, Wait and the rest"
    case (.wait, .code):
        "a code screen has nothing to wait for; Wait [marker] waits for narration"
    case (.wait, .terminal):
        "a terminal screen has no elements; Wait /regex/, Wait quiet or Wait exit wait for its output"
    case let (.zoom(target, _, _), _) where target.isElement:
        "\(screen.name) zooms on a point (Zoom @x,y) or the cursor, not an element"
    case let (.key(combo, _), .code)
        where !combo.modifiers.subtracting(.shift).isEmpty || !ScreenKeys.supported.contains(combo.key):
        "a code screen's editor takes the keys \(ScreenKeys.supported.sorted().joined(separator: ", ")), "
            + "with shift to select, not \(combo.description)"
    case let (.key(combo, _), .terminal) where TerminalKeys.bytes(for: combo) == nil:
        "a terminal screen takes the keys \(TerminalKeys.names.sorted().joined(separator: ", ")) and ctrl+<letter>, "
            + "not \(combo.description)"
    default:
        nil
    }
}

/// `/pattern/` as a pattern, checked now rather than when the take waits on it.
private func regex(_ text: String, fail: (String) -> TapeError) throws -> String {
    guard text.count > 2, text.hasPrefix("/"), text.hasSuffix("/") else {
        throw fail("a pattern is written between slashes: /Build complete/, not '\(text)'")
    }
    let pattern = String(text.dropFirst().dropLast())
    do {
        _ = try NSRegularExpression(pattern: pattern)
    } catch {
        throw fail("/\(pattern)/ is not a pattern reel can read: \(error.localizedDescription)")
    }
    return pattern
}

/// What a terminal's keys send to the shell.
enum TerminalKeys {
    static let sequences: [String: String] = [
        "return": "\r", "enter": "\r", "tab": "\t", "space": " ", "backspace": "\u{7f}", "delete": "\u{7f}",
        "forwarddelete": "\u{1b}[3~", "escape": "\u{1b}", "esc": "\u{1b}",
        "up": "\u{1b}[A", "down": "\u{1b}[B", "right": "\u{1b}[C", "left": "\u{1b}[D",
        "home": "\u{1b}[H", "end": "\u{1b}[F", "pageup": "\u{1b}[5~", "pagedown": "\u{1b}[6~",
    ]
    static var names: Set<String> {
        Set(sequences.keys)
    }

    /// The bytes for `combo`: a named key without modifiers, or ctrl with a letter (`ctrl+c`); nil for anything else.
    static func bytes(for combo: KeyCombo) -> String? {
        if combo.modifiers.isEmpty { return sequences[combo.key] }
        guard combo.modifiers == .control, combo.key.count == 1, let letter = combo.key.unicodeScalars.first,
              ("a" ... "z").contains(letter)
        else { return nil }
        return String(UnicodeScalar(UInt8(letter.value - 96)))
    }
}

/// The keys a code screen's editor takes.
enum ScreenKeys {
    static let supported: Set<String> = [
        "return", "enter", "tab", "space", "backspace", "delete", "forwarddelete", "escape", "esc",
        "up", "down", "left", "right", "home", "end", "pageup", "pagedown",
    ]
}

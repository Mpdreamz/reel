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
    /// `Set Background`: the recording is framed on it in every output; nil frames only outputs with a shape.
    public var background: Background?
    /// Room around a framed recording, as a share of the canvas's shorter side.
    public var padding: Double
    public var launch: LaunchTarget
    /// The commands after setup, in order. Recording starts before the first one.
    public var steps: [Step]

    public static let defaultFrameRate = 60
    public static let defaultTypingSpeed = Duration.milliseconds(50)
    public static let defaultWaitTimeout = Duration.seconds(10)
    public static let defaultGifFrameRate = 15
    public static let defaultGifWidth = 800
    public static let defaultGifColors = 256

    /// What every tape starts with, and the error a tape gets when it does not.
    static let preface = "a tape starts with Launch <app> or Open <url> (after any Import lines), which says what it records"

    /// Whether playing the tape needs Accessibility: anything that finds, moves or types into the app.
    public var drivesTheApp: Bool {
        size != nil || steps.contains {
            switch $0.command {
            case .sleep, .caption, .say, .reach, .speed, .hide: false
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
    public enum Shape: Equatable, Sendable, CustomStringConvertible {
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

    public var isWeb: Bool {
        if case .web = self { true } else { false }
    }
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
                    "the tape Sets Browser chromium, but none is installed (Chrome, Chromium, Brave, Edge) or "
                        + "downloaded by Playwright (`npx playwright install chromium`)"
                )
            }
            return .chromium(app)
        case let .app(app):
            guard exists(app) else { throw ReelError("the tape Sets Browser \(app.path), which is not there") }
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
}

public enum Command: Equatable, Sendable {
    case sleep(Duration)
    case click(Target)
    case wait(Target)
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

    /// Drawn or edited at render time only: recording skips it, so it can change without a new take.
    public var isRenderOnly: Bool {
        switch self {
        case .caption, .speed, .hide: true
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
    static let listSettings: Set<String> = ["Profiles", "Formats"]

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
                message: "the tape renders \(profiles.joined(separator: ", ")); '\(outside)' is not one of them"
            )
        }
        let names = chosen.isEmpty ? profiles : chosen
        return names.isEmpty ? [nil] : names.map { profile(named: $0) }
    }

    func profile(named name: String) -> Profile? {
        known.first { $0.name == name }
    }

    static func load(_ url: URL) throws -> Tape {
        guard url.pathExtension == "reel" else {
            throw TapeError(message: "\(url.lastPathComponent) is not a reel script; those are .reel files")
        }
        return try parse(String(contentsOf: url, encoding: .utf8), relativeTo: url.deletingLastPathComponent())
    }

    /// Parses a tape. Relative paths (`Output`, `Launch` of an `.app`) resolve against `directory`. With a profile,
    /// its settings apply after the tape's own.
    static func parse(
        _ text: String, relativeTo directory: URL, profile: Profile? = nil, format: Output.Format? = nil
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
        var introBackground: Background?, outroBackground: Background?
        var launch: (target: LaunchTarget, line: Int)?
        var steps: [Step] = []

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
            func forWeb(_ what: String) throws {
                if !isWeb { throw fail("\(what) is for web pages (Open); this tape Launches an app") }
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
                try forWeb("Set Viewport")
                guard let parsed = parseSize(value) else {
                    throw fail("Viewport must be <width>x<height> in points, such as 1280x800, not '\(value)'")
                }
                web.viewport = parsed
            case "Size":
                if isWeb { throw fail("Set Size is an app's window; a web page's size is Set Viewport") }
                guard let parsed = parseSize(value) else {
                    throw fail("Size must be <width>x<height> in points, such as 1280x800, not '\(value)'")
                }
                size = parsed
            case "Voice":
                voice.source = try VoiceSource(value, fail: fail)
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
                        + "IntroBackground, OutroBackground, Browser, Viewport, Background or Padding"
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
                case "Caption", "Intro", "Outro":
                    args = try Condition.choose(args, profile: profile?.name, format: format, names: &names, fail: fail)
                default:
                    throw fail(
                        "a condition (?) works in Set, Caption, Intro and Outro, which render decides; \(command) "
                            + "happens when recording, the same for every profile"
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
                steps.append(Step(line: line, source: tokens.map(\.source).joined(separator: " "), command: command))
            }
            // `Type@20ms`: a command may carry an option after `@`; only Type takes one.
            let (name, option) = first.quoted ? (first.text, nil) : split(first.text)
            if option != nil, !["Type", "Say", "Zoom", "Intro", "Outro", "Output"].contains(name) {
                throw fail("\(name) takes no @option")
            }
            // The first line says what the tape records; everything after is read knowing it.
            if launch == nil, !["Launch", "Open", "Import"].contains(name) { throw fail(Tape.preface) }
            let isWeb = launch?.target.isWeb == true

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
                let usage = "expected \(name) \"<title>\" [\"<subtitle>\"] [duration]"
                guard (1 ... 3).contains(args.count), args[0].quoted else { throw fail(usage) }
                var rest = args.dropFirst()
                let subtitle = rest.first?.quoted == true ? rest.popFirst()?.text : nil
                let length = try rest.popFirst().map { try duration($0.text, fail: fail) }
                guard rest.isEmpty else { throw fail(usage) }
                let section = try Section(
                    title: args[0].text, subtitle: subtitle, duration: length,
                    transition: option.map { try SectionTransition($0, fail: fail) } ?? .standard
                )
                if name == "Intro" {
                    guard intro == nil else { throw fail("a tape has one Intro") }
                    intro = section
                } else {
                    guard outro == nil else { throw fail("a tape has one Outro") }
                    outro = section
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
                guard words.count == 2 || (words.count > 2 && Tape.listSettings.contains(words[0])) else {
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
                    guard isWeb else { throw fail("Open goes to a web page; this tape Launches an app") }
                    step(.open(url))
                }

            case "Launch":
                try setup(name)
                let target = try single(words, usage: "Launch <bundle id or .app path>", fail: fail)
                if let earlier = launch {
                    throw fail(
                        isWeb ? "a web tape Opens pages; line \(earlier.line) already does, so there is no app to Launch"
                            : "a tape launches one app; line \(earlier.line) already does"
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

            case "Sleep":
                let value = try single(words, usage: "Sleep <duration>", fail: fail)
                try step(.sleep(duration(value, fail: fail)))

            case "Click":
                guard args.count == 1
                else { throw fail("expected Click \"<label>\", Click #<identifier> or Click @x,y") }
                try step(.click(target(args[0], fail: fail)))

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
                guard option == nil || option == "over"
                else { throw fail("Say takes @over or nothing, not @\(option!)") }
                let text = try single(words, usage: "Say \"<text>\"", fail: fail)
                let speech = try Speech(text, fail: fail)
                for name in speech.markers {
                    if let earlier = markers[name] {
                        throw fail("[\(name)] is already a marker on line \(earlier.line)")
                    }
                    markers[name] = (line, option == "over")
                }
                step(.say(speech, over: option == "over"))

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
                    "Zoom", "Speed", "Hide", "Show", "Intro", "Outro", "Open",
                ]
                let hint = known.first { $0.lowercased() == name.lowercased() }.map { "; did you mean \($0)?" }
                throw fail("unknown command '\(name)'" + (hint ?? "; expected one of \(known.joined(separator: ", "))"))
            }
        }

        guard let launch else { throw TapeError(message: Tape.preface) }
        guard !outputs.isEmpty else { throw TapeError(message: "the tape has no Output") }
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
        if !launch.target.isWeb {
            for step in steps
                where step.command.targets.contains(where: { if case .css = $0 { true } else { false } })
            {
                throw TapeError(line: step.line, message: "css: targets are for web pages; Open one instead of Launch")
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
            background: background,
            padding: padding,
            launch: launch.target,
            steps: steps
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

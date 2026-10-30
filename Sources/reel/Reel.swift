import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation
import ReelCore

@main
struct Reel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reel",
        abstract: "Record demos of macOS apps and web pages from a .reel script: video with sound, GIFs, captions.",
        version: reelVersion,
        subcommands: [Run.self, Record.self, Render.self, Check.self, Profiles.self, Doctor.self],
        defaultSubcommand: Run.self
    )
}

struct TapeArgument: ParsableArguments {
    @Argument(help: "The .reel to play.", completion: .file(extensions: ["reel"]))
    var reel: String

    var url: URL {
        URL(fileURLWithPath: (reel as NSString).expandingTildeInPath).standardizedFileURL
    }

    func load() throws -> Tape {
        let tape = try Tape.load(url)
        tape.warnings.forEach(warn)
        return tape
    }
}

struct ProfileOption: ParsableArguments {
    @Option(
        name: .customLong("profile"),
        help: ArgumentHelp(
            "Render only these profiles (repeat it, or separate with commas); a reel that lists its profiles "
                + "(Set Profiles) renders only from among them. See reel profiles.",
            valueName: "name"
        )
    )
    var names: [String] = []

    var chosen: [String] {
        names.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
    }
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Record the reel, then render every Output.")

    @OptionGroup var tape: TapeArgument
    @OptionGroup var profiles: ProfileOption

    func run() async throws {
        let parsed = try tape.load()
        // Refused before recording, not after: every profile is read, its settings checked.
        for profile in try parsed.profilesToRender(chosen: profiles.chosen) {
            _ = try parsed.with(profile: profile)
        }
        let location = TakeLocation(tape: tape.url)
        _ = try await Recorder.record(parsed, into: location, log: say)
        try await Renderer.render(tape: parsed, from: location, profiles: profiles.chosen, log: say)
    }
}

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Only capture the take, into .reel/<reel name>/.")

    @OptionGroup var tape: TapeArgument

    func run() async throws {
        let location = TakeLocation(tape: tape.url)
        let take = try await Recorder.record(tape.load(), into: location, log: say)
        say("take: \(location.directory.path) (\(take.width)×\(take.height), \(take.durationMs) ms)")
    }
}

struct Render: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Only render the Outputs from the reel's last take.")

    @OptionGroup var tape: TapeArgument
    @OptionGroup var profiles: ProfileOption

    func run() async throws {
        try await Renderer.render(
            tape: tape.load(), from: TakeLocation(tape: tape.url), profiles: profiles.chosen, log: say
        )
    }
}

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Parse the reel and say what it would do.")

    @OptionGroup var tape: TapeArgument
    @OptionGroup var profiles: ProfileOption

    func run() async throws {
        let parsed = try tape.load()
        let rendered = try parsed.profilesToRender(chosen: profiles.chosen)
        switch parsed.launch {
        case let .bundleID(id): say("launch \(id)")
        case let .app(url): say("launch \(url.path)")
        case let .web(url):
            say("open \(url.absoluteString) at \(Int(parsed.web.viewport.width))x\(Int(parsed.web.viewport.height))")
        }
        say("capture at \(parsed.frameRate) fps, audio \(parsed.audio ? "on" : "off")")
        let lines = parsed.steps.count(where: { if case .say = $0.command { true } else { false } })
        if lines > 0 {
            say(
                "narration: \(lines) line\(lines == 1 ? "" : "s") in \(parsed.voice.source)\(parsed.voice.subtitles ? ", subtitled" : "")"
            )
        }
        if parsed.audio, !parsed.outputs.contains(where: \.format.hasSound) {
            say("note: audio is on but every Output is a GIF, which has no sound")
        }
        let captions = parsed.steps.filter(\.command.isCaption).count
        say(
            "\(parsed.actions.count) action\(parsed.actions.count == 1 ? "" : "s"), \(captions) caption\(captions == 1 ? "" : "s")"
        )
        for profile in rendered {
            let read = profile == nil ? parsed : try parsed.with(profile: profile)
            if let profile { say("profile \(profile.name): \(profile.purpose)") }
            for output in read.outputs {
                say("output \(output.url.path)")
            }
            for output in read.skipped {
                say("skips \(output.url.lastPathComponent): \(profile?.name ?? "the tape") writes no .\(output.format)")
            }
        }
    }
}

struct Profiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the profiles a reel can render for, and what each sets.",
        discussion: "Set Profiles github, social in a reel renders every Output once for each, as name-github.mp4 "
            + "and name-social.mp4; --profile on run, render and check picks among them. Given a reel, the list "
            + "has what its presets and the reel itself define and amend, with where each setting comes from."
    )

    @Argument(
        help: "A .reel whose profiles to list; without one, the built-in ones.",
        completion: .file(extensions: ["reel"])
    )
    var reel: String?

    func run() async throws {
        let known = try reel.map { try TapeArgument.parse([$0]).load().known } ?? Profile.builtIn
        for profile in known {
            say("\(profile.name): \(profile.purpose)")
            for setting in profile.settings {
                say("  Set \(setting.name) \(setting.value)" + (setting.origin.map { "    # \($0)" } ?? ""))
            }
        }
    }
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report the permissions reel needs, without asking for them, and the browsers web reels can use."
    )

    func run() async throws {
        let screen = CGPreflightScreenCaptureAccess()
        let accessibility = AXIsProcessTrusted()
        say("Screen Recording: \(screen ? "granted" : "not granted (needed to record)")")
        say(
            "Accessibility:    \(accessibility ? "granted" : "not granted (needed by tapes that click, type or scroll)")"
        )
        // Not permissions, and not needed by every tape: reported, never a failure.
        say("Web pages:        WebKit, built in (Set Browser chromium for Chromium)")
        let chromium = Browser.locate().map(\.description) ?? "none found (for Set Browser chromium: install Chrome, "
            + "Chromium, Brave or Edge, or `npx playwright install chromium`)"
        say("Chromium:         " + chromium)
        if !screen {
            say("Grant them to this terminal in System Settings → Privacy & Security.")
            throw ExitCode(1)
        }
    }
}

private func say(_ line: String) {
    print(line)
}

private func warn(_ line: String) {
    FileHandle.standardError.write(Data("warning: \(line)\n".utf8))
}

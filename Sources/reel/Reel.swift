import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation
import ReelCore

@main
struct Reel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reel",
        abstract: "Record demos of macOS apps from a .tape script: video with the app's sound.",
        subcommands: [Run.self, Record.self, Render.self, Check.self, Doctor.self],
        defaultSubcommand: Run.self
    )
}

struct TapeArgument: ParsableArguments {
    @Argument(help: "The .tape to play.", completion: .file(extensions: ["tape"]))
    var tape: String

    var url: URL {
        URL(fileURLWithPath: (tape as NSString).expandingTildeInPath).standardizedFileURL
    }

    func load() throws -> Tape {
        try Tape.load(url)
    }
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Record the tape, then render every Output.")

    @OptionGroup var tape: TapeArgument

    func run() async throws {
        let parsed = try tape.load()
        let location = TakeLocation(tape: tape.url)
        _ = try await Recorder.record(parsed, into: location, log: say)
        try await renderAll(parsed, from: location)
    }
}

struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Only capture the take, into .reel/<tape name>/.")

    @OptionGroup var tape: TapeArgument

    func run() async throws {
        let location = TakeLocation(tape: tape.url)
        let take = try await Recorder.record(tape.load(), into: location, log: say)
        say("take: \(location.directory.path) (\(take.width)×\(take.height), \(take.durationMs) ms)")
    }
}

struct Render: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Only render the Outputs from the tape's last take.")

    @OptionGroup var tape: TapeArgument

    func run() async throws {
        try await renderAll(tape.load(), from: TakeLocation(tape: tape.url))
    }
}

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Parse the tape and say what it would do.")

    @OptionGroup var tape: TapeArgument

    func run() async throws {
        let parsed = try tape.load()
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
        for output in parsed.outputs {
            say("output \(output.url.path)")
        }
    }
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report the permissions reel needs, without asking for them, and the browsers web tapes can use."
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

private func renderAll(_ tape: Tape, from location: TakeLocation) async throws {
    try await Renderer.render(tape: tape, from: location, log: say)
}

private func say(_ line: String) {
    print(line)
}

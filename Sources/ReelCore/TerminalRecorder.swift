import Foundation

extension Recorder {
    /// How long a shell has to show its first prompt.
    static let promptTimeout: Duration = .seconds(10)
    /// A pause after each `Key`, as a person's would be.
    static let terminalKeyGap: Duration = .milliseconds(120)

    /// A terminal screen, in two passes. The shell runs for real, in real time, and everything it prints is kept with
    /// when it printed it; then the take is drawn from that, a frame at a time on the take's own clock, as a code
    /// screen is. Nothing is captured from the screen, and no permission is needed.
    static func recordTerminal(
        _ tape: Tape, narration: Narration, into location: TakeLocation, log: (String) -> Void
    ) async throws -> Take {
        let settings = tape.terminal
        let folder = settings.workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // On the reel's own channel, or one of its own: a reel run in the shell talks to this one either way.
        let channel = try Channel.fromEnvironment() ?? Channel
            .fresh(at: location.directory.appending(path: "channel.jsonl"))
        let session = try TerminalSession(
            columns: settings.columns, rows: settings.rows, folder: folder, channel: channel.url
        )
        defer { session.close() }
        log("running zsh in \(folder.path), \(settings.columns)×\(settings.rows)")
        let deadline = ContinuousClock.now + promptTimeout
        while !session.exited(since: 0) {
            if session.hasEnded { throw ReelError("the shell ended before its first prompt") }
            if ContinuousClock.now > deadline { throw ReelError("the shell showed no prompt within \(promptTimeout)") }
            try await Task.sleep(for: .milliseconds(20))
        }
        session.startClock()

        var events: [Take.Event] = []
        /// What the drawing pass does besides printing: marks and callouts, at their times.
        var drawn: [(ms: Int, line: Int, step: Pointer)] = []
        var clock = SpeechClock()
        // Where the output a wait looks at starts: what was printed after the last thing typed or pressed, so a wait
        // for /done/ after `echo done` and return finds the command's output, not the command.
        var since = session.mark
        var afterReturn = false
        func output() -> String {
            Self.waitedOn(session.text(since: since), afterReturn: afterReturn)
        }
        func sleep(until ms: Int) async throws {
            let wait = ms - session.now
            if wait > 0 { try await Task.sleep(for: .milliseconds(wait)) }
        }
        func waitFor(_ what: String, _ done: () -> Bool) async throws {
            let deadline = ContinuousClock.now + tape.waitTimeout
            while !done() {
                if ContinuousClock.now > deadline {
                    let lines = output().split(separator: "\n").suffix(3)
                    throw ReelError(
                        "waited \(tape.waitTimeout.written) for \(what)"
                            +
                            (lines.isEmpty ? "; nothing was printed" : "; the last lines were:\n" + lines
                                .joined(separator: "\n"))
                    )
                }
                if session.hasEnded { throw ReelError("the shell ended while waiting for \(what)") }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        for step in tape.steps where !step.command.isRenderOnly {
            var begin = session.now
            var clip: String?
            channel.post(reel: location.reelName, line: step.line, name: step.name, phase: .start)
            do {
                switch step.command {
                case let .sleep(duration):
                    try await Task.sleep(for: duration)
                case let .waitFor(name, end):
                    try await channel.wait(for: name, end: end, timeout: tape.waitTimeout)
                case let .say(_, over):
                    guard let line = narration.lines[step.line]
                    else { throw ReelError("line \(step.line) was not voiced") }
                    let (spoken, resume) = clock.say(line, now: Double(session.now) / 1000, over: over)
                    begin = Int((spoken * 1000).rounded())
                    clip = line.key
                    try await sleep(until: Int((resume * 1000).rounded()))
                case let .reach(marker):
                    if let time = clock.time(of: marker) { try await sleep(until: Int((time * 1000).rounded())) }
                case let .type(text, pause):
                    since = session.mark
                    afterReturn = false
                    for character in text {
                        try session.write(String(character))
                        try await Task.sleep(for: pause ?? tape.typingSpeed)
                    }
                case let .key(combo, count):
                    guard let bytes = TerminalKeys.bytes(for: combo) else {
                        throw ReelError("a terminal screen takes no key \(combo.description)")
                    }
                    since = session.mark
                    afterReturn = bytes == "\r"
                    for _ in 0 ..< count {
                        try session.write(bytes)
                        try await Task.sleep(for: terminalKeyGap)
                    }
                case let .expect(.output(pattern)):
                    let regex = try NSRegularExpression(pattern: pattern)
                    try await waitFor("/\(pattern)/") {
                        let text = output()
                        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
                    }
                case let .expect(.quiet(duration)):
                    try await waitFor("\(duration.written) without output") { session.quiet >= duration }
                case .expect(.exit):
                    try await waitFor("the command to end") { session.exited(since: since) }
                case let .mark(text, number):
                    drawn.append((session.now, step.line, .mark(text, number)))
                    try await Task.sleep(for: .milliseconds(screenTimings.mark))
                case let .callout(text, label):
                    drawn.append((session.now, step.line, .callout(text, label)))
                    try await Task.sleep(for: .milliseconds(screenTimings.mark))
                default:
                    // The parser keeps everything else out of a terminal screen.
                    throw ReelError("a terminal screen cannot \(step.source)")
                }
            } catch let error as ReelError {
                throw ReelError("line \(step.line): \(error.description)")
            }
            events.append(Take.Event(
                line: step.line, command: step.source, startMs: begin, endMs: session.now, clip: clip
            ))
            channel.post(reel: location.reelName, line: step.line, name: step.name, phase: .end)
        }
        try await sleep(until: Int((clock.speechEnd * 1000).rounded()))
        let end = session.now
        let output = session.output
        session.close()

        let take = try await drawTerminal(
            output, pointers: drawn, until: end, events: events, tape: tape, folder: folder, into: location, log: log
        )
        try location.write(take)
        return take
    }

    /// What a wait looks at of what was printed since the last input. After a return, that starts past the end of the
    /// command line: the shell echoes what is typed as it reads it, and a command typed quickly can still be echoing
    /// when return is pressed, so `echo done` would otherwise count as the `done` a wait is for.
    static func waitedOn(_ printed: String, afterReturn: Bool) -> String {
        guard afterReturn else { return printed }
        guard let end = printed.firstIndex(of: "\n") else { return "" }
        return String(printed[printed.index(after: end)...])
    }

    /// The second pass: the terminal drawn from what the shell printed and when, and the marks and callouts at their
    /// times. The same output draws the same take.
    static func drawTerminal(
        _ output: [(ms: Int, text: String)], pointers: [(ms: Int, line: Int, step: Pointer)], until end: Int,
        events: [Take.Event], tape: Tape, folder: URL, into location: TakeLocation, log: (String) -> Void
    ) async throws -> Take {
        let settings = tape.terminal
        let page = try await ScreenPage("terminal.html", size: CGSize(width: 2400, height: 1600), options: [
            "columns": settings.columns, "rows": settings.rows, "fontSize": tape.fontSize,
            "theme": TerminalTheme.load(settings.theme), "title": settings.title ?? "\(folder.lastPathComponent) — zsh",
            "redactions": settings.redactions,
        ])
        let size = try await page.measure()
        await page.resize(to: size)
        try await page.step("return reelScreen.layout()")
        let film = try ScreenFilm(page: page, size: size, into: location, frameRate: tape.frameRate)
        log("drawing the terminal, \(film.width)×\(film.height)")
        var marks = pointers[...]
        func point(_ next: (ms: Int, line: Int, step: Pointer)) async throws {
            try await film.advance(to: next.ms)
            do {
                try await next.step.draw(on: page)
            } catch let error as ReelError {
                throw ReelError("line \(next.line): \(error.description)")
            }
        }
        for piece in output {
            while let next = marks.first, next.ms <= piece.ms {
                try await point(next)
                marks.removeFirst()
            }
            try await film.advance(to: piece.ms)
            try await page.step("await reelScreen.feed(t); return null", ["t": piece.text])
        }
        for next in marks {
            try await point(next)
        }
        try await film.advance(to: end)
        return try await film.finish(events: events, log: log)
    }
}

/// A mark or a callout on a terminal screen, drawn at its time over what was printed by then.
enum Pointer: Sendable {
    case mark(String?, Int?)
    case callout(String?, String?)

    func draw(on page: ScreenPage) async throws {
        switch self {
        case let .mark(text, number):
            try await page.step("return reelScreen.mark(t, n)", ["t": text ?? NSNull(), "n": number ?? NSNull()])
        case let .callout(text, label):
            try await page.step("return reelScreen.callout(t, l)", ["t": text ?? NSNull(), "l": label ?? NSNull()])
        }
    }
}

/// A terminal's colours: reel's own, or a Ghostty theme's (`Set Theme`), as xterm.js takes them.
enum TerminalTheme {
    /// reel's dark theme, as `design/brand/themes/reel-dark.ghostty` has it.
    static let reel = """
    background = 111923
    foreground = E7ECF1
    cursor-color = F2B04C
    cursor-text = 111923
    selection-background = 2a3b4e
    selection-foreground = E7ECF1
    palette = 0=#1d2b3a
    palette = 1=#F29E84
    palette = 2=#7FD1C0
    palette = 3=#F2B04C
    palette = 4=#86B6F2
    palette = 5=#E58FB8
    palette = 6=#5CC8B6
    palette = 7=#E7ECF1
    palette = 8=#5d7388
    palette = 9=#F7B8A4
    palette = 10=#9FE0D2
    palette = 11=#F7C877
    palette = 12=#A7CDF7
    palette = 13=#EFB0CF
    palette = 14=#86DCCB
    palette = 15=#FFFFFF
    """

    static let names = [
        "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "brightBlack", "brightRed",
        "brightGreen", "brightYellow", "brightBlue", "brightMagenta", "brightCyan", "brightWhite",
    ]

    /// The theme in `file`, reel's when nil.
    static func load(_ file: URL?) throws -> [String: String] {
        guard let file else { return parse(reel) }
        do {
            return try parse(String(contentsOf: file, encoding: .utf8))
        } catch {
            throw ReelError("cannot read the theme \(file.path): \(error.localizedDescription)")
        }
    }

    /// Ghostty's `key = value` lines: `background`, `foreground`, `cursor-color`, `cursor-text`,
    /// `selection-background`, `selection-foreground` and `palette = n=#rrggbb`. Anything else is left out.
    static func parse(_ text: String) -> [String: String] {
        let keys = [
            "background": "background", "foreground": "foreground", "cursor-color": "cursor",
            "cursor-text": "cursorAccent", "selection-background": "selectionBackground",
            "selection-foreground": "selectionForeground",
        ]
        var theme: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].hasPrefix("#") else { continue }
            if parts[0] == "palette" {
                let entry = parts[1].split(separator: "=", maxSplits: 1)
                if entry.count == 2, let n = Int(entry[0]), names.indices.contains(n),
                   let colour = hex(String(entry[1]))
                {
                    theme[names[n]] = colour
                }
            } else if let key = keys[parts[0]], let colour = hex(parts[1]) {
                theme[key] = colour
            }
        }
        return theme
    }

    /// `#rrggbb` from `rrggbb` or `#rrggbb`; nil for anything else.
    private static func hex(_ text: String) -> String? {
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits
    }
}

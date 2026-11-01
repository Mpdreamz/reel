import CoreMedia
import Foundation

extension Recorder {
    /// How long the code screen's own moves take, in its clock: a file coming up, the view scrolling to a place, a
    /// focus dimming the rest, a mark or callout appearing. The take waits for each, as it would watch an app's.
    static let screenTimings: (open: Int, go: Int, focus: Int, mark: Int, key: Int) = (300, 400, 350, 180, 120)
    /// The same for splitting the screen, switching panes, a peek opening and a link drawing itself.
    static let paneTimings: (split: Int, pane: Int, peek: Int, link: Int) = (450, 100, 320, 500)
    /// How a morph moves when its reel says nothing.
    static let morphMotion = Transition(easing: .easeInOut, duration: .milliseconds(900))
    /// The most lines a peek shows; it scrolls to its place in the file.
    static let peekLines = 8

    /// A code screen: no app and no capture. The steps play on a clock of the take's own, and each frame is drawn when
    /// its time comes, so a take is the same every time and takes as long as drawing it does.
    static func recordScreen(
        _ tape: Tape, narration: Narration, into location: TakeLocation, log: (String) -> Void
    ) async throws -> Take {
        let viewport = tape.web.viewport
        let screen = try await ScreenPage(
            "screen.html", size: viewport, options: ["fontSize": tape.fontSize, "peekLines": peekLines]
        )
        let film = try ScreenFilm(page: screen, size: viewport, into: location, frameRate: tape.frameRate)
        log("drawing the code screen, \(film.width)×\(film.height)")
        var now: Int {
            film.now
        }
        func advance(to time: Int) async throws {
            try await film.advance(to: time)
        }

        var events: [Take.Event] = []
        var clock = SpeechClock()
        try await advance(to: 0)
        for step in tape.steps where !step.command.isRenderOnly {
            var begin = now
            var clip: String?
            do {
                switch step.command {
                case let .sleep(duration):
                    try await advance(to: now + milliseconds(duration))
                case let .say(_, over):
                    guard let line = narration.lines[step.line]
                    else { throw ReelError("line \(step.line) was not voiced") }
                    let (spoken, resume) = clock.say(line, now: Double(now) / 1000, over: over)
                    begin = Int((spoken * 1000).rounded())
                    clip = line.key
                    try await advance(to: Int((resume * 1000).rounded()))
                case let .reach(marker):
                    if let time = clock.time(of: marker) { try await advance(to: Int((time * 1000).rounded())) }
                case let .code(file, transition):
                    try await screen.step(
                        "return await reelScreen.open(f, t)", ["f": screenFile(file), "t": transition?.page ?? NSNull()]
                    )
                    try await advance(to: now + (transition.map { milliseconds($0.duration) } ?? screenTimings.open))
                case let .diff(source, transition):
                    try await screen.step(
                        "return await reelScreen.open(f, t)",
                        ["f": screenDiff(source), "t": transition?.page ?? NSNull()]
                    )
                    try await advance(to: now + (transition.map { milliseconds($0.duration) } ?? screenTimings.open))
                case let .morph(file, motion):
                    let (easing, seconds) = (motion ?? Transition(easing: nil, duration: nil)).over(morphMotion)
                    let ms = Int((seconds * 1000).rounded())
                    try await screen.step(
                        "return await reelScreen.morph(f, m)",
                        ["f": screenFile(file), "m": ["easing": easing.rawValue, "ms": ms]]
                    )
                    try await advance(to: now + ms)
                case let .split(file):
                    try await screen.step("return await reelScreen.split(f)", ["f": file.map(screenFile) ?? NSNull()])
                    try await advance(to: now + paneTimings.split)
                case let .pane(side):
                    try await screen.step("return reelScreen.pane(i)", ["i": side])
                    try await advance(to: now + paneTimings.pane)
                case let .peek(text, file):
                    try await screen.step(
                        "return await reelScreen.peek(t, f)",
                        ["t": text ?? NSNull(), "f": file.map(screenFile) ?? NSNull()]
                    )
                    try await advance(to: now + paneTimings.peek)
                case let .link(from, to, label):
                    try await screen.step(
                        "return reelScreen.link(a, b, l)",
                        ["a": from ?? NSNull(), "b": to ?? NSNull(), "l": label ?? NSNull()]
                    )
                    try await advance(to: now + paneTimings.link)
                case let .go(anchor):
                    try await screen.step("return reelScreen.go(a)", ["a": anchor.page])
                    try await advance(to: now + screenTimings.go)
                case let .type(text, pause):
                    let gap = milliseconds(pause ?? tape.typingSpeed)
                    for character in text {
                        try await screen.step("return reelScreen.type(t)", ["t": String(character)])
                        try await advance(to: now + gap)
                    }
                case let .key(combo, count):
                    for _ in 0 ..< count {
                        try await screen.step(
                            "return reelScreen.key(k, s)", ["k": combo.key, "s": combo.modifiers.contains(.shift)]
                        )
                        try await advance(to: now + screenTimings.key)
                    }
                case let .focus(range):
                    try await screen.step(
                        "return reelScreen.focus(r)", ["r": range.map { [$0.lowerBound, $0.upperBound] } ?? NSNull()]
                    )
                    try await advance(to: now + screenTimings.focus)
                case let .mark(text, number):
                    try await screen.step(
                        "return reelScreen.mark(t, n)", ["t": text ?? NSNull(), "n": number ?? NSNull()]
                    )
                    try await advance(to: now + screenTimings.mark)
                case let .callout(text, label):
                    try await screen.step(
                        "return reelScreen.callout(t, l)", ["t": text ?? NSNull(), "l": label ?? NSNull()]
                    )
                    try await advance(to: now + screenTimings.mark)
                default:
                    // The parser keeps everything else out of a code screen.
                    throw ReelError("a code screen cannot \(step.source)")
                }
            } catch let error as ReelError {
                throw ReelError("line \(step.line): \(error.description)")
            }
            events.append(Take.Event(line: step.line, command: step.source, startMs: begin, endMs: now, clip: clip))
        }
        // The take runs until the last line has been said.
        try await advance(to: Int((clock.speechEnd * 1000).rounded()))
        let take = try await film.finish(events: events, log: log)
        try location.write(take)
        return take
    }

    /// What the page needs to show a file: its text (only `lines a-b` of it when given), what to call it, and where.
    static func screenFile(_ file: CodeFile) throws -> [String: Any] {
        let text: String
        do {
            text = try String(contentsOf: file.url, encoding: .utf8)
        } catch {
            throw ReelError("cannot read \(file.url.path): \(error.localizedDescription)")
        }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var first = 1
        if let range = file.lines {
            guard range.upperBound <= lines.count else {
                throw ReelError(
                    "\(file.url.lastPathComponent) has \(lines.count) lines, not \(range.lowerBound)-\(range.upperBound)"
                )
            }
            lines = Array(lines[(range.lowerBound - 1) ..< range.upperBound])
            first = range.lowerBound
        }
        return [
            "name": file.url.lastPathComponent,
            "directory": folderName(of: file.url),
            "text": lines.joined(separator: "\n"),
            "firstLine": first,
            "at": file.at.map(\.page) ?? NSNull(),
        ]
    }

    /// The folder a file is in, as its header shows it: from the git root, or just its name outside a repository.
    static func folderName(of file: URL) -> String {
        let folder = file.deletingLastPathComponent()
        guard let root = Paths.gitRoot(from: folder) else { return folder.lastPathComponent }
        return String(folder.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// What the page needs to show a diff: the two versions as one, each line's kind and number in the new file,
    /// the words that changed, where the hunks start, and what it compares, for its header.
    static func screenDiff(_ source: DiffSource) throws -> [String: Any] {
        func read(_ url: URL) throws -> String {
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw ReelError("cannot read \(url.path): \(error.localizedDescription)")
            }
        }
        let after = try read(source.after)
        let before: String, label: String
        switch source.before {
        case let .file(url):
            before = try read(url)
            label = "\(url.lastPathComponent) → \(source.after.lastPathComponent)"
        case let .revision(revision):
            let folder = source.after.deletingLastPathComponent()
            before = try git(["show", "\(revision):./\(source.after.lastPathComponent)"], in: folder)
            let short = try git(["rev-parse", "--short", revision], in: folder)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            label = short == revision ? "since \(revision)" : "since \(revision) (\(short))"
        }
        let diff = CodeDiff(before: before, after: after)
        return [
            "name": source.after.lastPathComponent,
            "directory": folderName(of: source.after),
            "text": diff.rows.map(\.text).joined(separator: "\n"),
            "firstLine": 1,
            "at": source.at.map(\.page) ?? NSNull(),
            "diff": [
                "kinds": diff.rows.map(\.kind.rawValue),
                "numbers": diff.rows.map { $0.number.map { $0 as Any } ?? NSNull() },
                "words": diff.rows.map { $0.words.map { [$0.lowerBound, $0.upperBound] } },
                "hunks": diff.hunks,
                "added": diff.added,
                "removed": diff.removed,
                "label": label,
            ] as [String: Any],
        ]
    }

    /// What git prints for `arguments`, run in `folder`; what it says went wrong when it fails.
    static func git(_ arguments: [String], in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            throw ReelError("cannot run git: \(error.localizedDescription)")
        }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let problem = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ReelError("git \(arguments.joined(separator: " ")): "
                + problem.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: output, as: UTF8.self)
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
    }
}

extension CodeAnchor {
    /// As the page takes it: `{ line: 40 }` or `{ text: "func play" }`.
    var page: [String: Any] {
        switch self {
        case let .line(n): ["line": n]
        case let .text(text): ["text": text]
        case let .hunk(n): ["hunk": n]
        }
    }
}

/// A screen's take as it is drawn: each frame due as the take's clock moves on, snapshotted and written to the take's
/// movie. A frame is only written when the page changed; a still screen holds the one before, as a capture of a still
/// window does.
final class ScreenFilm {
    /// The pixels a point of a screen: what a Retina display records.
    static let scale = 2.0

    let page: ScreenPage
    let width: Int
    let height: Int
    let frameRate: Int
    /// The take's clock, in milliseconds.
    private(set) var now = 0
    private var shown = 0
    private var frameCount = 0
    /// Where the caret was: what `Zoom cursor` follows.
    private var caretTrack: [Take.Sample] = []
    private let writer: TakeWriter
    private let frames: FrameMaker

    init(page: ScreenPage, size: CGSize, into location: TakeLocation, frameRate: Int) throws {
        self.page = page
        self.frameRate = frameRate
        width = Recorder.even(size.width * Self.scale)
        height = Recorder.even(size.height * Self.scale)
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        writer = try TakeWriter(
            url: location.movie, width: width, height: height, frameRate: frameRate, audio: false, realTime: false
        )
        frames = try FrameMaker(width: width, height: height)
    }

    private func frameTime(_ n: Int) -> Int {
        Int((Double(n) * 1000 / Double(frameRate)).rounded())
    }

    /// Draws every frame due up to `time`.
    func advance(to time: Int) async throws {
        now = max(now, time)
        while frameTime(frameCount) <= now {
            let at = frameTime(frameCount)
            let (changed, caret) = try await page.pump(at - shown)
            shown = at
            if changed || frameCount == 0 {
                let image = try await page.snapshot(scale: Self.scale)
                nonisolated(unsafe) let sample = try frames.frame(image, at: at, frameRate: frameRate)
                await writer.perform { [writer] in writer.append(video: sample) }
            }
            if let caret, caretTrack.last.map({ $0.x != caret.x || $0.y != caret.y }) ?? true {
                caretTrack.append(Take.Sample(ms: at, frame: CGRect(origin: caret, size: .zero)))
            }
            frameCount += 1
        }
    }

    /// Ends the movie at the clock's time, and the take that goes with it.
    func finish(events: [Take.Event], log: (String) -> Void) async throws -> Take {
        try await writer.finish(at: CMTime(value: CMTimeValue(now), timescale: 1000))
        if writer.droppedFrames > 0 { log("dropped \(writer.droppedFrames) frames the encoder was not ready for") }
        var take = Take(
            width: width, height: height, scale: Self.scale, frameRate: frameRate, audio: false, durationMs: now,
            events: events
        )
        // The caret is what `Zoom cursor` follows; nothing draws a pointer over it.
        take.cursor = caretTrack
        return take
    }
}

extension SectionTransition {
    /// As the page takes it: `{ kind: "slide-left", easing: "ease-out", ms: 600 }`.
    var page: [String: Any] {
        ["kind": kind.rawValue, "easing": easing.rawValue, "ms": Recorder.milliseconds(duration)]
    }
}

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

    /// A page call a code screen's step makes, and when: what the drawing pass replays.
    struct CodeCall {
        var ms: Int
        var line: Int
        var body: String
        var arguments: [String: Any]
    }

    /// A code screen: no app and no capture, in two passes, as a terminal is. The steps play first, writing down each
    /// call to the page and when; then the page is drawn from that, a frame at a time, so a take is the same every
    /// time. Alone, the steps play on the take's own clock, at once. On a channel, with other reels, they keep real
    /// time, so what they say there lines up with what the others do.
    static func recordScreen(
        _ tape: Tape, narration: Narration, into location: TakeLocation, channel: Channel?, as runner: String? = nil,
        log: (String) -> Void
    ) async throws -> Take {
        let startedAt = Channel.now
        let played = try await playCode(
            tape, narration: narration, reel: location.reelName, channel: channel, startedAt: startedAt, as: runner,
            log: log
        )
        var take = try await drawCode(
            played.calls, until: played.end, events: played.events, tape: tape, into: location, log: log
        )
        take.startedAt = startedAt
        try location.write(take)
        return take
    }

    /// What a code screen's steps play: the calls to its page and when, its timeline, and when it ends.
    struct Played {
        var calls: [CodeCall]
        var events: [Take.Event]
        var end: Int
    }

    /// The first pass: the steps, played on the take's clock (real time on a channel), writing down each call to the
    /// page. `startedAt` is the wall clock at its time 0, which `Follow` times what it hears on the channel by.
    static func playCode(
        _ tape: Tape, narration: Narration, reel: String, channel: Channel?, startedAt: Int, as runner: String? = nil,
        log: (String) -> Void
    ) async throws -> Played {
        let clock = TakeClock(real: channel != nil)
        var now: Int {
            clock.now
        }
        func advance(to time: Int) async throws {
            try await clock.wait(until: time)
        }

        var events: [Take.Event] = []
        let calls = CallLog()
        var speech = SpeechClock()
        // Which file each pane shows, and which pane steps act on: what `Follow` follows.
        var shown: [Int: String] = [:]
        var active = 0
        var following: (pane: Int, task: Task<Void, Never>)?
        func stopFollowing() {
            following?.task.cancel()
            following = nil
        }
        defer { stopFollowing() }
        for step in tape.steps where !step.command.isRenderOnly {
            var begin = now
            var clip: String?
            channel?.post(reel: reel, line: step.line, name: step.name, phase: .start)
            // Throws only as its arguments do: reading a file can.
            func call(_ body: String, _ arguments: [String: Any]) throws {
                calls.append(CodeCall(ms: now, line: step.line, body: body, arguments: arguments))
            }
            // A pane given another file stops following the one it showed.
            func show(_ name: String, in pane: Int) {
                if following?.pane == pane { stopFollowing() }
                shown[pane] = name
            }
            do {
                switch step.command {
                case let .sleep(duration):
                    try await advance(to: now + milliseconds(duration))
                case let .waitFor(name, end):
                    // The other reel keeps real time: the take's clock moves on by as long as the wait took.
                    let started = ContinuousClock.now
                    try await Channel.wait(
                        channel, for: name, end: end, timeout: tape.waitTimeout, line: step.line, as: runner, log: log
                    )
                    try await advance(to: now + milliseconds(ContinuousClock.now - started))
                case let .say(_, over):
                    guard let line = narration.lines[step.line]
                    else { throw ReelError("line \(step.line) was not voiced") }
                    let (spoken, resume) = speech.say(line, now: Double(now) / 1000, over: over)
                    begin = Int((spoken * 1000).rounded())
                    clip = line.key
                    try await advance(to: Int((resume * 1000).rounded()))
                case let .reach(marker):
                    if let time = speech.time(of: marker) { try await advance(to: Int((time * 1000).rounded())) }
                case let .follow(on):
                    stopFollowing()
                    guard on else {
                        try call("return reelScreen.follow(null, p)", ["p": active])
                        break
                    }
                    guard let channel else {
                        log(
                            "line \(step.line): skipped Follow: no reel runs with this one (\(Channel.variable) is not set)"
                        )
                        break
                    }
                    guard let name = shown[active]
                    else { throw ReelError("Follow follows the reel a pane shows: Code it first") }
                    following = (active, follow(
                        name,
                        on: channel,
                        into: calls,
                        pane: active,
                        from: now,
                        startedAt: startedAt,
                        line: step.line
                    ))
                case let .code(file, transition):
                    show(file.url.lastPathComponent, in: active)
                    try call(
                        "return await reelScreen.open(f, t)", ["f": screenFile(file), "t": transition?.page ?? NSNull()]
                    )
                    try await advance(to: now + (transition.map { milliseconds($0.duration) } ?? screenTimings.open))
                case let .diff(source, transition):
                    show(source.after.lastPathComponent, in: active)
                    try call(
                        "return await reelScreen.open(f, t)",
                        ["f": screenDiff(source), "t": transition?.page ?? NSNull()]
                    )
                    try await advance(to: now + (transition.map { milliseconds($0.duration) } ?? screenTimings.open))
                case let .morph(file, motion):
                    show(file.url.lastPathComponent, in: active)
                    let (easing, seconds) = (motion ?? Transition(easing: nil, duration: nil)).over(morphMotion)
                    let ms = Int((seconds * 1000).rounded())
                    try call(
                        "return await reelScreen.morph(f, m)",
                        ["f": screenFile(file), "m": ["easing": easing.rawValue, "ms": ms]]
                    )
                    try await advance(to: now + ms)
                case let .split(file):
                    if let file {
                        show(file.url.lastPathComponent, in: 1)
                        active = 1
                    } else {
                        if following?.pane == 1 { stopFollowing() }
                        shown[1] = nil
                        active = 0
                    }
                    try call("return await reelScreen.split(f)", ["f": file.map(screenFile) ?? NSNull()])
                    try await advance(to: now + paneTimings.split)
                case let .pane(side):
                    active = side
                    try call("return reelScreen.pane(i)", ["i": side])
                    try await advance(to: now + paneTimings.pane)
                case let .peek(text, file):
                    try call(
                        "return await reelScreen.peek(t, f)",
                        ["t": text ?? NSNull(), "f": file.map(screenFile) ?? NSNull()]
                    )
                    try await advance(to: now + paneTimings.peek)
                case let .link(from, to, label):
                    try call(
                        "return reelScreen.link(a, b, l)",
                        ["a": from ?? NSNull(), "b": to ?? NSNull(), "l": label ?? NSNull()]
                    )
                    try await advance(to: now + paneTimings.link)
                case let .go(anchor):
                    try call("return reelScreen.go(a)", ["a": anchor.page])
                    try await advance(to: now + screenTimings.go)
                case let .type(text, pause):
                    let gap = milliseconds(pause ?? tape.typingSpeed)
                    for character in text {
                        try call("return reelScreen.type(t)", ["t": String(character)])
                        try await advance(to: now + gap)
                    }
                case let .key(combo, count):
                    for _ in 0 ..< count {
                        try call(
                            "return reelScreen.key(k, s)", ["k": combo.key, "s": combo.modifiers.contains(.shift)]
                        )
                        try await advance(to: now + screenTimings.key)
                    }
                case let .focus(range):
                    try call(
                        "return reelScreen.focus(r)", ["r": range.map { [$0.lowerBound, $0.upperBound] } ?? NSNull()]
                    )
                    try await advance(to: now + screenTimings.focus)
                case let .mark(text, number):
                    try call(
                        "return reelScreen.mark(t, n)", ["t": text ?? NSNull(), "n": number ?? NSNull()]
                    )
                    try await advance(to: now + screenTimings.mark)
                case let .callout(text, label):
                    try call(
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
            channel?.post(reel: reel, line: step.line, name: step.name, phase: .end)
        }
        // The take runs until the last line has been said.
        try await advance(to: Int((speech.speechEnd * 1000).rounded()))
        stopFollowing()
        return Played(calls: calls.all, events: events, end: now)
    }

    /// Watches the channel for the steps of the reel `name` starting, each a call that highlights its line in `pane`,
    /// at the moment it started on the take's clock (one already started counts from `from`, so the latest shows).
    static func follow(
        _ name: String, on channel: Channel, into calls: CallLog, pane: Int, from: Int, startedAt: Int, line: Int
    ) -> Task<Void, Never> {
        Task {
            var heard = 0
            while !Task.isCancelled {
                let events = channel.events
                for event in events.dropFirst(heard) where event.reel == name && event.phase == .start {
                    calls.append(CodeCall(
                        ms: max(from, event.at - startedAt), line: line,
                        body: "return reelScreen.follow(l, p)", arguments: ["l": event.line, "p": pane]
                    ))
                }
                heard = events.count
                try? await Task.sleep(for: Channel.poll)
            }
        }
    }

    /// The second pass: the page, each call made at its time, a frame drawn whenever one is due. A call the page
    /// refuses (text that is not in the file) stops it, naming its line.
    static func drawCode(
        _ calls: [CodeCall], until end: Int, events: [Take.Event], tape: Tape, into location: TakeLocation,
        log: (String) -> Void
    ) async throws -> Take {
        let viewport = tape.web.viewport
        let screen = try await ScreenPage(
            "screen.html", size: viewport, options: ["fontSize": tape.fontSize, "peekLines": peekLines]
        )
        let film = try ScreenFilm(page: screen, size: viewport, into: location, frameRate: tape.frameRate)
        log("drawing the code screen, \(film.width)×\(film.height)")
        try await film.advance(to: 0)
        for call in calls {
            try await film.advance(to: call.ms)
            // Made on this pass, read only by the page: nothing else holds them.
            nonisolated(unsafe) let arguments = call.arguments
            do {
                try await screen.step(call.body, arguments)
            } catch let error as ReelError {
                throw ReelError("line \(call.line): \(error.description)")
            }
        }
        try await film.advance(to: end)
        return try await film.finish(events: events, log: log)
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

/// A take's clock, in milliseconds. Its own (`real` false), which moves on as far as it is told at once, or real time,
/// which it waits for. In real time it is never behind: a step that ran late moves what follows on, so a `Sleep 400ms`
/// still lasts 400ms and the take shows what happened when it happened.
final class TakeClock {
    let real: Bool
    private let start = ContinuousClock.now
    private var reached = 0

    init(real: Bool) {
        self.real = real
    }

    /// Where the take is: as far as it has been told, and in real time, never earlier than now.
    var now: Int {
        real ? max(reached, Recorder.milliseconds(ContinuousClock.now - start)) : reached
    }

    func wait(until time: Int) async throws {
        if real {
            let due = start + .milliseconds(time)
            if due > ContinuousClock.now { try await Task.sleep(until: due) }
        }
        reached = max(reached, time)
    }
}

/// The calls a code screen's steps make, and those `Follow` adds as it hears them: written from two tasks at once.
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Recorder.CodeCall] = []

    func append(_ call: Recorder.CodeCall) {
        lock.withLock { calls.append(call) }
    }

    /// In the order they are made: by time, and as written where two share one.
    var all: [Recorder.CodeCall] {
        lock
            .withLock {
                calls.enumerated().sorted { ($0.element.ms, $0.offset) < ($1.element.ms, $1.offset) }.map(\.element)
            }
    }
}

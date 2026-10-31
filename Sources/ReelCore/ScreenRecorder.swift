import CoreMedia
import Foundation

extension Recorder {
    /// The pixels a point of a code screen: what a Retina display records.
    static let screenScale = 2.0
    /// How long the code screen's own moves take, in its clock: a file coming up, the view scrolling to a place, a
    /// focus dimming the rest, a mark or callout appearing. The take waits for each, as it would watch an app's.
    static let screenTimings: (open: Int, go: Int, focus: Int, mark: Int, key: Int) = (300, 400, 350, 180, 120)

    /// A code screen: no app and no capture. The steps play on a clock of the take's own, and each frame is drawn when
    /// its time comes, so a take is the same every time and takes as long as drawing it does.
    static func recordScreen(
        _ tape: Tape, narration: Narration, into location: TakeLocation, log: (String) -> Void
    ) async throws -> Take {
        let viewport = tape.web.viewport
        let screen = try await CodeScreen(size: viewport, fontSize: tape.fontSize)
        let width = even(viewport.width * screenScale), height = even(viewport.height * screenScale)
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let writer = try TakeWriter(
            url: location.movie, width: width, height: height, frameRate: tape.frameRate, audio: false,
            realTime: false
        )
        let frames = try FrameMaker(width: width, height: height)
        log("drawing the code screen, \(width)×\(height)")

        /// The take's clock, in milliseconds, and the next frame due on it.
        var now = 0
        var shown = 0
        var frameCount = 0
        var caretTrack: [Take.Sample] = []
        let interval = 1000.0 / Double(tape.frameRate)
        func frameTime(_ n: Int) -> Int { Int((Double(n) * interval).rounded()) }

        /// Draws every frame due up to `time`: a frame is only written when the page changed, and a still screen holds
        /// the one before, as a capture of a still window does.
        func advance(to time: Int) async throws {
            now = max(now, time)
            while frameTime(frameCount) <= now {
                let at = frameTime(frameCount)
                let (changed, caret) = try await screen.pump(at - shown)
                shown = at
                if changed || frameCount == 0 {
                    let image = try await screen.snapshot(scale: screenScale)
                    nonisolated(unsafe) let sample = try frames.frame(image, at: at, frameRate: tape.frameRate)
                    await writer.perform { writer.append(video: sample) }
                }
                if let caret, caretTrack.last.map({ $0.x != caret.x || $0.y != caret.y }) ?? true {
                    caretTrack.append(Take.Sample(ms: at, frame: CGRect(origin: caret, size: .zero)))
                }
                frameCount += 1
            }
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
                case let .code(file):
                    try await screen.step("return await reelScreen.open(f)", ["f": screenFile(file)])
                    try await advance(to: now + screenTimings.open)
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
        try await writer.finish(at: CMTime(value: CMTimeValue(now), timescale: 1000))
        if writer.droppedFrames > 0 { log("dropped \(writer.droppedFrames) frames the encoder was not ready for") }

        var take = Take(
            width: width, height: height, scale: screenScale, frameRate: tape.frameRate, audio: false,
            durationMs: now, events: events
        )
        // The caret is what `Zoom cursor` follows; nothing draws a pointer over it.
        take.cursor = caretTrack
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
        let folder = file.url.deletingLastPathComponent()
        let directory: String = if let root = Paths.gitRoot(from: folder) {
            String(folder.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            folder.lastPathComponent
        }
        return [
            "name": file.url.lastPathComponent,
            "directory": directory,
            "text": lines.joined(separator: "\n"),
            "firstLine": first,
            "at": file.at.map(\.page) ?? NSNull(),
        ]
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
        }
    }
}

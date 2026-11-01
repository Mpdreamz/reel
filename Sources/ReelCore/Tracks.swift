import Foundation

/// A reel that records several subjects at once: a terminal, a code screen, an app, each a track of its own, written
/// indented under its line (`Screen terminal as term`) or in a file (`With term.reel as term`). Every track records
/// as its own reel would, into `.reel/<reel>/tracks/<name>/`, all at the same time, on one channel, so they wait for
/// each other's named steps (`Wait for`). The reel's unindented steps are the director's: what is said over them all,
/// and when.
public enum Tracks {
    /// Where a track's take goes.
    public static func location(of track: Track, in location: TakeLocation) -> TakeLocation {
        TakeLocation(directory: location.directory.appending(path: "tracks/\(track.name)", directoryHint: .isDirectory))
    }

    /// Where the director's timeline goes: what was said, and when, from the moment the tracks started.
    static func director(in location: TakeLocation) -> URL {
        location.directory.appending(path: "director.json")
    }

    /// Records every track and the director at once. The first to fail stops the others.
    public static func record(_ tape: Tape, into location: TakeLocation, log: @escaping @Sendable (String) -> Void)
        async throws
    {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let channel = try Channel.fromEnvironment()
            ?? Channel.fresh(at: location.directory.appending(path: "channel.jsonl"))
        var names = Set(tape.steps.compactMap(\.name))
        for track in tape.tracks {
            names.formUnion(track.tape.steps.compactMap(\.name))
        }
        channel.expect(names)
        // Voiced before anything starts: a voice that cannot be reached fails here, not halfway through.
        let narration = try await Narration.prepare(
            tape, into: location.directory, voices: tape.voice.synthesizer(for:), log: log
        )
        log("recording \(tape.tracks.count) tracks at once: \(tape.tracks.map(\.name).joined(separator: ", "))")
        let startedAt = Channel.now
        for track in tape.tracks {
            channel.join(track.name)
        }
        channel.join("director")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for track in tape.tracks {
                group.addTask {
                    defer { channel.leave(track.name) }
                    do {
                        _ = try await Recorder.record(
                            track.tape, into: Self.location(of: track, in: location), channel: channel,
                            as: track.name, log: { log("\(track.name): \($0)") }
                        )
                    } catch {
                        throw ReelError("\(track.name): \(error.localizedDescription)")
                    }
                }
            }
            group.addTask {
                defer { channel.leave("director") }
                let take = try await direct(
                    tape, narration: narration, channel: channel, startedAt: startedAt, reel: location.reelName,
                    log: log
                )
                try JSONEncoder().encode(take).write(to: director(in: location))
            }
            // The first to fail stops the others: a track waiting for one that failed would only wait.
            do {
                try await group.waitForAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// The director's track, in real time from `startedAt`: narration, waits for the tracks, and pauses. What it
    /// draws (captions) is placed at render time from these events, as in any reel.
    static func direct(
        _ tape: Tape, narration: Narration, channel: Channel, startedAt: Int, reel: String,
        log _: (String) -> Void
    ) async throws -> Take {
        let start = ContinuousClock.now
        func now() -> Int {
            Recorder.milliseconds(ContinuousClock.now - start)
        }
        func sleep(until ms: Int) async throws {
            let due = start + .milliseconds(ms)
            if due > ContinuousClock.now { try await Task.sleep(until: due) }
        }
        var events: [Take.Event] = []
        var speech = SpeechClock()
        for step in tape.steps where !step.command.isRenderOnly {
            channel.post(reel: reel, line: step.line, name: step.name, phase: .start)
            var begin = now()
            var clip: String?
            do {
                switch step.command {
                case let .sleep(duration):
                    try await Task.sleep(for: duration)
                case let .say(_, over):
                    guard let line = narration.lines[step.line] else { throw ReelError("it was not voiced") }
                    let (spoken, resume) = speech.say(line, now: Double(now()) / 1000, over: over)
                    begin = Int((spoken * 1000).rounded())
                    clip = line.key
                    try await sleep(until: Int((resume * 1000).rounded()))
                case let .reach(marker):
                    if let time = speech.time(of: marker) { try await sleep(until: Int((time * 1000).rounded())) }
                case let .waitFor(name, end):
                    try await channel.wait(for: name, end: end, timeout: tape.waitTimeout, as: "director")
                default:
                    // The parser keeps everything else in the tracks.
                    throw ReelError("the director cannot \(step.source)")
                }
            } catch let error as ReelError {
                throw ReelError("line \(step.line): \(error.description)")
            }
            events.append(Take.Event(line: step.line, command: step.source, startMs: begin, endMs: now(), clip: clip))
            channel.post(reel: reel, line: step.line, name: step.name, phase: .end)
        }
        try await sleep(until: Int((speech.speechEnd * 1000).rounded()))
        var take = Take(
            width: 0,
            height: 0,
            scale: 1,
            frameRate: tape.frameRate,
            audio: false,
            durationMs: now(),
            events: events
        )
        take.startedAt = startedAt
        return take
    }
}

import AVFoundation
import Foundation
@_exported import ReelEvents

/// What a run says it is doing, as `RunEvent`s, to the sink the command line sets for the task (`Events.$sink`).
/// Task-local, as is what an event is about (the track, the profile, the Output), so the recorders and the renderer
/// say it where it happens without every call between them passing it on. Without a sink nothing is said.
public enum Events {
    @TaskLocal public static var sink: (any EventSink)?
    /// The track of a reel of tracks being recorded.
    @TaskLocal public static var track: String?
    @TaskLocal static var profile: String?
    @TaskLocal static var output: String?
    @TaskLocal static var detail: String?
    /// The pass running now, which `report` tells how far along it is.
    @TaskLocal static var current: Reporter?

    public static func emit(_ kind: RunEvent.Kind) {
        guard let sink else { return }
        sink.emit(RunEvent(at: Runs.now, pid: ProcessInfo.processInfo.processIdentifier, track: track, kind: kind))
    }

    /// Runs `body` as a pass named `name`: said at 0 when it starts and at 1 when it ends, and in between as far as
    /// `report` says, at most ten times a second.
    static func pass<T>(
        _ name: RunEvent.Pass.Name, attempt: Int? = nil, _ body: () async throws -> T
    ) async throws -> T {
        guard let sink else { return try await body() }
        let reporter = Reporter(
            RunEvent.Pass(name: name, profile: profile, output: output, detail: detail, attempt: attempt, fraction: 0),
            sink: sink, track: track
        )
        reporter.say(0, always: true)
        let result = try await $current.withValue(reporter) { try await body() }
        reporter.say(1, always: true)
        return result
    }

    /// How far the pass running now is, 0 to 1.
    static func report(_ fraction: Double) {
        current?.say(fraction)
    }

    /// `body`, its passes said to be for `output`.
    static func about<T>(output: Output, _ body: () async throws -> T) async throws -> T {
        try await $output.withValue(output.url.lastPathComponent) { try await body() }
    }

    /// Says a pass's progress: never backwards, and not more often than `interval` unless it ends.
    final class Reporter: @unchecked Sendable {
        static let interval = 0.1
        private let lock = NSLock()
        private var pass: RunEvent.Pass
        private let sink: any EventSink
        private let track: String?
        private var said = -1.0
        private var saidAt = Date.distantPast

        init(_ pass: RunEvent.Pass, sink: any EventSink, track: String?) {
            self.pass = pass
            self.sink = sink
            self.track = track
        }

        func say(_ fraction: Double, always: Bool = false) {
            let fraction = min(1, max(0, fraction.isFinite ? fraction : 0))
            let event: RunEvent? = lock.withLock {
                guard fraction > said || (always && fraction == 1 && said < 1) || (always && said < 0) else {
                    return nil
                }
                let now = Date()
                guard always || now.timeIntervalSince(saidAt) >= Self.interval else { return nil }
                said = fraction
                saidAt = now
                pass.fraction = fraction
                return RunEvent(
                    at: Runs.now, pid: ProcessInfo.processInfo.processIdentifier, track: track, kind: .pass(pass)
                )
            }
            if let event { sink.emit(event) }
        }
    }
}

/// Says each step a recorder plays, as the how-manieth of the steps that record.
final class StepCount {
    let count: Int
    private var index = 0

    init(_ tape: Tape) {
        count = tape.steps.count(where: { !$0.command.isRenderOnly })
    }

    func start(_ step: Step) {
        index += 1
        Events.emit(.step(line: step.line, source: step.source, index: index, count: count, phase: .start))
    }

    func end(_ step: Step) {
        Events.emit(.step(line: step.line, source: step.source, index: index, count: count, phase: .end))
    }
}

extension AVAssetExportSession {
    /// Exports as `export(to:as:)` does, as the pass `name`, its progress read ten times a second.
    func exportReporting(to url: URL, as type: AVFileType, pass name: RunEvent.Pass.Name) async throws {
        try await Events.pass(name) {
            let states = states(updateInterval: Events.Reporter.interval)
            let watch = Task {
                for await state in states {
                    if Task.isCancelled { break }
                    if case let .exporting(progress) = state { Events.report(progress.fractionCompleted) }
                }
            }
            defer { watch.cancel() }
            try await export(to: url, as: type)
        }
    }
}

import Foundation

/// What a run's events add up to so far: what the companion app shows of it.
public struct RunState: Equatable, Sendable, Identifiable {
    public var id: Int32 {
        pid
    }

    public let pid: Int32
    /// The reel's path, its command, and what it renders, from `started`.
    public var reel = ""
    public var command = ""
    public var startedAt: Int?
    public var scenes: [String] = []
    public var profiles: [String] = []
    public var outputs: [String] = []
    /// The scene recording now, of a reel of scenes.
    public var scene: Scene?
    /// The step each subject is on: the reel's own under "", a track's under its name.
    public var steps: [String: Step] = [:]
    /// What is being captured now, by subject as `steps` is.
    public var captures: [String: Capture] = [:]
    /// The latest pass, of any subject.
    public var pass: RunEvent.Pass?
    public var written: [Written] = []
    /// The last line the run printed.
    public var note: String?
    public var failure: String?
    /// Whether it ended well; nil while it runs.
    public var ok: Bool?
    /// The run's process went without saying it ended: it crashed, or was killed.
    public var gone = false
    /// When the last event was said.
    public var updatedAt = 0

    public init(pid: Int32) {
        self.pid = pid
    }

    public struct Scene: Equatable, Sendable {
        public var index, count: Int
        public var reel: String
    }

    public struct Step: Equatable, Sendable {
        public var line: Int
        public var source: String
        public var index, count: Int
        public var running: Bool
    }

    public struct Capture: Equatable, Sendable {
        /// The part of the screen recorded, nil for a screen reel draws itself.
        public var window: RunEvent.Rect?
        /// The processes kept out of it.
        public var excluded: Set<Int32>
    }

    public struct Written: Equatable, Sendable {
        public var path: String
        public var summary: String
    }

    public enum Stage: Equatable, Sendable {
        case starting, recording, rendering, finished, failed, gone
    }

    public var stage: Stage {
        if let ok { return ok ? .finished : .failed }
        if gone { return .gone }
        if !captures.isEmpty { return .recording }
        if pass != nil { return .rendering }
        return steps.isEmpty ? .starting : .recording
    }

    /// The reel's file name.
    public var name: String {
        URL(fileURLWithPath: reel).lastPathComponent
    }

    /// The captures `companion`'s windows are kept out of, by subject: where it may draw over what is recorded.
    public func overlays(for companion: Int32) -> [(subject: String, window: RunEvent.Rect)] {
        captures.compactMap { subject, capture in
            guard let window = capture.window, capture.excluded.contains(companion) else { return nil }
            return (subject, window)
        }.sorted { $0.subject < $1.subject }
    }

    public mutating func apply(_ event: RunEvent) {
        updatedAt = max(updatedAt, event.at)
        let subject = event.track ?? ""
        switch event.kind {
        case let .started(reel, command, scenes, profiles, outputs):
            self.reel = reel
            self.command = command
            self.scenes = scenes
            self.profiles = profiles
            self.outputs = outputs
            startedAt = event.at
        case let .scene(index, count, reel):
            scene = Scene(index: index, count: count, reel: reel)
            steps = [:]
        case let .step(line, source, index, count, phase):
            steps[subject] = Step(line: line, source: source, index: index, count: count, running: phase == .start)
        case let .recording(phase, window, excluded):
            switch phase {
            case .start: captures[subject] = Capture(window: window, excluded: Set(excluded))
            case .end: captures[subject] = nil
            }
        case let .excluded(pids):
            captures[subject]?.excluded.formUnion(pids)
        case let .pass(pass):
            self.pass = pass
        case let .wrote(path, summary):
            written.append(Written(path: path, summary: summary))
        case let .note(text):
            note = text
        case let .failed(text):
            failure = text
        case let .ended(ok):
            self.ok = ok
            captures = [:]
        }
    }
}

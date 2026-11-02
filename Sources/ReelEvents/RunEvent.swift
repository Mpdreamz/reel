import Foundation

/// What a run of reel is doing, as it does it: one JSON line per event, for anyone watching (the companion app, a
/// script). Each says when, which process, which track of a reel of tracks, and what happened. Nothing reads these
/// back into reel: they never change what a run does.
public struct RunEvent: Equatable, Sendable {
    /// Milliseconds since 1970, the clock the channel uses too.
    public var at: Int
    /// The reel process that said it.
    public var pid: Int32
    /// The track of a reel of tracks it is about; nil for the reel itself, or the director.
    public var track: String?
    public var kind: Kind

    public init(at: Int, pid: Int32, track: String? = nil, kind: Kind) {
        self.at = at
        self.pid = pid
        self.track = track
        self.kind = kind
    }

    public enum Phase: String, Codable, Sendable {
        case start, end
    }

    /// A rectangle in global points, the top left of the main display at 0,0 and y down (as ScreenCaptureKit and
    /// Accessibility have it).
    public struct Rect: Codable, Equatable, Sendable {
        public var x, y, width, height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// A stretch of work with a known end, and how far along it is.
    public struct Pass: Codable, Equatable, Sendable {
        public enum Name: String, Codable, Sendable, CaseIterable {
            /// A code or terminal screen drawn from what its steps did, a frame at a time.
            case draw
            /// The take cut, zoomed, narrated and drawn over.
            case render
            /// A recording put on its canvas.
            case frame
            /// Scenes joined, or an intro and outro put around a demo.
            case join
            /// The tracks of a reel of tracks drawn together.
            case tracks
            /// A movie Output compressed.
            case encode
            /// A GIF Output drawn.
            case gif
        }

        public var name: Name
        /// The profile being rendered (`Set Profiles`), nil without one.
        public var profile: String?
        /// The Output's file name this pass is for, when it is for one.
        public var output: String?
        /// More about what it works on: "scene 2 of 3".
        public var detail: String?
        /// The how-manieth try at it, when a pass is redone to fit `MaxSize`.
        public var attempt: Int?
        /// 0 to 1.
        public var fraction: Double

        public init(
            name: Name, profile: String? = nil, output: String? = nil, detail: String? = nil, attempt: Int? = nil,
            fraction: Double
        ) {
            self.name = name
            self.profile = profile
            self.output = output
            self.detail = detail
            self.attempt = attempt
            self.fraction = fraction
        }
    }

    public enum Kind: Equatable, Sendable {
        /// A run starts: the reel's path, the command (`run`, `record`, `render`), its scenes' file names, the profiles
        /// it renders and its Outputs' file names.
        case started(reel: String, command: String, scenes: [String], profiles: [String], outputs: [String])
        /// A scene of a reel of scenes starts recording: 1-based.
        case scene(index: Int, count: Int, reel: String)
        /// A step starts or ends: its line, as written, and which of the steps that record it is (1-based) of how many.
        case step(line: Int, source: String, index: Int, count: Int, phase: Phase)
        /// Capture starts or ends. At the start: the part of the screen recorded (nil for a screen reel draws itself,
        /// which shows nowhere), and the processes kept out of it.
        case recording(phase: Phase, window: Rect?, excluded: [Int32])
        /// Processes kept out of a capture that is already running: apps that started after it.
        case excluded([Int32])
        /// How far a pass is.
        case pass(Pass)
        /// An Output is written, with what the command line said of it.
        case wrote(path: String, summary: String)
        /// A line the command line printed.
        case note(String)
        /// The run failed: what it said.
        case failed(String)
        /// The run is over.
        case ended(ok: Bool)
    }
}

extension RunEvent: Codable {
    private enum Keys: String, CodingKey {
        case at, pid, track, kind
        case reel, command, scenes, profiles, outputs
        case index, count, line, source, phase
        case window, excluded, pass, path, summary, text, ok
    }

    private enum Tag: String, Codable {
        case started, scene, step, recording, excluded, pass, wrote, note, failed, ended
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        at = try c.decode(Int.self, forKey: .at)
        pid = try c.decode(Int32.self, forKey: .pid)
        track = try c.decodeIfPresent(String.self, forKey: .track)
        switch try c.decode(Tag.self, forKey: .kind) {
        case .started:
            kind = try .started(
                reel: c.decode(String.self, forKey: .reel), command: c.decode(String.self, forKey: .command),
                scenes: c.decode([String].self, forKey: .scenes), profiles: c.decode([String].self, forKey: .profiles),
                outputs: c.decode([String].self, forKey: .outputs)
            )
        case .scene:
            kind = try .scene(
                index: c.decode(Int.self, forKey: .index), count: c.decode(Int.self, forKey: .count),
                reel: c.decode(String.self, forKey: .reel)
            )
        case .step:
            kind = try .step(
                line: c.decode(Int.self, forKey: .line), source: c.decode(String.self, forKey: .source),
                index: c.decode(Int.self, forKey: .index), count: c.decode(Int.self, forKey: .count),
                phase: c.decode(Phase.self, forKey: .phase)
            )
        case .recording:
            kind = try .recording(
                phase: c.decode(Phase.self, forKey: .phase), window: c.decodeIfPresent(Rect.self, forKey: .window),
                excluded: c.decodeIfPresent([Int32].self, forKey: .excluded) ?? []
            )
        case .excluded:
            kind = try .excluded(c.decode([Int32].self, forKey: .excluded))
        case .pass:
            kind = try .pass(c.decode(Pass.self, forKey: .pass))
        case .wrote:
            kind = try .wrote(
                path: c.decode(String.self, forKey: .path),
                summary: c.decode(String.self, forKey: .summary)
            )
        case .note:
            kind = try .note(c.decode(String.self, forKey: .text))
        case .failed:
            kind = try .failed(c.decode(String.self, forKey: .text))
        case .ended:
            kind = try .ended(ok: c.decode(Bool.self, forKey: .ok))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(at, forKey: .at)
        try c.encode(pid, forKey: .pid)
        try c.encodeIfPresent(track, forKey: .track)
        switch kind {
        case let .started(reel, command, scenes, profiles, outputs):
            try c.encode(Tag.started, forKey: .kind)
            try c.encode(reel, forKey: .reel)
            try c.encode(command, forKey: .command)
            try c.encode(scenes, forKey: .scenes)
            try c.encode(profiles, forKey: .profiles)
            try c.encode(outputs, forKey: .outputs)
        case let .scene(index, count, reel):
            try c.encode(Tag.scene, forKey: .kind)
            try c.encode(index, forKey: .index)
            try c.encode(count, forKey: .count)
            try c.encode(reel, forKey: .reel)
        case let .step(line, source, index, count, phase):
            try c.encode(Tag.step, forKey: .kind)
            try c.encode(line, forKey: .line)
            try c.encode(source, forKey: .source)
            try c.encode(index, forKey: .index)
            try c.encode(count, forKey: .count)
            try c.encode(phase, forKey: .phase)
        case let .recording(phase, window, excluded):
            try c.encode(Tag.recording, forKey: .kind)
            try c.encode(phase, forKey: .phase)
            try c.encodeIfPresent(window, forKey: .window)
            try c.encode(excluded, forKey: .excluded)
        case let .excluded(pids):
            try c.encode(Tag.excluded, forKey: .kind)
            try c.encode(pids, forKey: .excluded)
        case let .pass(pass):
            try c.encode(Tag.pass, forKey: .kind)
            try c.encode(pass, forKey: .pass)
        case let .wrote(path, summary):
            try c.encode(Tag.wrote, forKey: .kind)
            try c.encode(path, forKey: .path)
            try c.encode(summary, forKey: .summary)
        case let .note(text):
            try c.encode(Tag.note, forKey: .kind)
            try c.encode(text, forKey: .text)
        case let .failed(text):
            try c.encode(Tag.failed, forKey: .kind)
            try c.encode(text, forKey: .text)
        case let .ended(ok):
            try c.encode(Tag.ended, forKey: .kind)
            try c.encode(ok, forKey: .ok)
        }
    }
}

public extension RunEvent {
    /// One line of JSON, with its newline.
    var line: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = (try? encoder.encode(self)) ?? Data()
        data.append(0x0A)
        return data
    }

    /// Every whole line of `data` that is an event; a line still being written, or one from a newer reel, is skipped.
    static func lines(_ data: Data) -> [RunEvent] {
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(RunEvent.self, from: Data($0)) }
    }
}

import Foundation

/// A recorded take: `take.mov` and this, `take.json`, in `.reel/<tape name>/` next to the tape. Render reads both;
/// overlays (later milestones) anchor to `events` rather than to seconds.
public struct Take: Codable, Equatable, Sendable {
    public static let version = 1

    public var version: Int
    /// Pixels of the captured window.
    public var width: Int
    public var height: Int
    /// Pixels per point of the display the window was on.
    public var scale: Double
    public var frameRate: Int
    public var audio: Bool
    /// From the first frame to the end of the last step.
    public var durationMs: Int
    public var events: [Event]

    public struct Event: Codable, Equatable, Sendable {
        public var line: Int
        public var command: String
        /// Milliseconds from the first frame.
        public var startMs: Int
        public var endMs: Int
        /// Where a click landed, in points from the window's top left.
        public var x: Double?
        public var y: Double?
        /// For a `Say`, the voiced line it played (`Narration.Line.key`); its start is when the line started.
        public var clip: String?

        public init(
            line: Int, command: String, startMs: Int, endMs: Int, x: Double? = nil, y: Double? = nil,
            clip: String? = nil
        ) {
            self.clip = clip
            self.line = line
            self.command = command
            self.startMs = startMs
            self.endMs = endMs
            self.x = x
            self.y = y
        }
    }

    public init(
        width: Int, height: Int, scale: Double, frameRate: Int, audio: Bool, durationMs: Int, events: [Event]
    ) {
        version = Self.version
        self.width = width
        self.height = height
        self.scale = scale
        self.frameRate = frameRate
        self.audio = audio
        self.durationMs = durationMs
        self.events = events
    }
}

/// Where a tape's take lives: `.reel/<tape name>/` next to the tape.
public struct TakeLocation: Sendable {
    public var directory: URL

    public init(tape: URL) {
        let name = tape.deletingPathExtension().lastPathComponent
        directory = tape.deletingLastPathComponent().appending(path: ".reel/\(name)", directoryHint: .isDirectory)
    }

    public var movie: URL {
        directory.appending(path: "take.mov")
    }

    public var timeline: URL {
        directory.appending(path: "take.json")
    }

    public func write(_ take: Take) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(take).write(to: timeline)
    }

    public func read() throws -> Take {
        guard FileManager.default.fileExists(atPath: movie.path), FileManager.default.fileExists(atPath: timeline.path)
        else {
            throw ReelError("no take in \(directory.path); record one first")
        }
        let take = try JSONDecoder().decode(Take.self, from: Data(contentsOf: timeline))
        guard take.version == Take.version else {
            throw ReelError("the take in \(directory.path) is version \(take.version); record it again")
        }
        return take
    }
}

public struct ReelError: Error, CustomStringConvertible, LocalizedError {
    public var description: String

    public init(_ description: String) {
        self.description = description
    }

    public var errorDescription: String? {
        description
    }
}

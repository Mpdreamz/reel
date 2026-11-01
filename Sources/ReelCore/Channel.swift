import Foundation

/// Where reels running at once tell each other what they do: a file of JSON lines, one when each step starts and one
/// when it ends, which every reel appends to and reads (`REEL_CHANNEL`). A step named `as <name>` is what another
/// reel waits for (`Wait for <name>`). A terminal screen gives its shell one, so a reel run in it is on the same
/// channel as the reel recording it.
public final class Channel: @unchecked Sendable {
    /// The environment variable a reel finds its channel in.
    public static let variable = "REEL_CHANNEL"
    /// How often a wait reads the channel again.
    static let poll: Duration = .milliseconds(20)

    public let url: URL
    private let lock = NSLock()
    /// For tracks recorded in this process: the names their steps have, who is still playing, and what each waits
    /// for. When every one of them waits for a step only they could take, nothing will ever come.
    private var local: Set<String> = []
    private var playing: Set<String> = []
    private var waiting: [String: String] = [:]

    public struct Event: Codable, Equatable, Sendable {
        public enum Phase: String, Codable, Sendable {
            case start, end
        }

        /// The reel's file name.
        public var reel: String
        public var line: Int
        public var name: String?
        public var phase: Phase
        /// Milliseconds since 1970: one clock for every reel.
        public var at: Int
    }

    public init(url: URL) {
        self.url = url
    }

    /// The channel named in this process's environment; nil when the reel runs alone.
    public static func fromEnvironment() -> Channel? {
        ProcessInfo.processInfo.environment[variable]
            .flatMap { $0.isEmpty ? nil : Channel(url: URL(fileURLWithPath: $0)) }
    }

    /// A channel of its own, empty, at `url`: for a terminal screen's shell when the reel is on none.
    static func fresh(at url: URL) throws -> Channel {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        return Channel(url: url)
    }

    /// Says that a step started or ended. One append each, which the file system keeps whole.
    func post(reel: String, line: Int, name: String?, phase: Event.Phase) {
        let event = Event(
            reel: reel, line: line, name: name, phase: phase, at: Int((Date().timeIntervalSince1970 * 1000).rounded())
        )
        guard var data = try? JSONEncoder().encode(event) else { return }
        data.append(0x0A)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// Everything said so far, in order.
    var events: [Event] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(Event.self, from: Data($0.utf8)) }
    }

    /// Tracks recorded in this process: `names` are what their steps are called.
    func expect(_ names: Set<String>) {
        lock.withLock { local.formUnion(names) }
    }

    /// `runner`, a track of this process, plays until it `leave`s.
    func join(_ runner: String) {
        _ = lock.withLock { playing.insert(runner) }
    }

    func leave(_ runner: String) {
        lock.withLock {
            playing.remove(runner)
            waiting[runner] = nil
        }
    }

    /// Who waits for what, when every track still playing waits for a step another of them would take: nil while
    /// any of them is doing something, or waits for a step that could come from outside.
    private func deadlock() -> String? {
        lock.withLock {
            guard !playing.isEmpty, playing.allSatisfy({ waiting[$0] != nil }),
                  waiting.values.allSatisfy(local.contains)
            else { return nil }
            return playing.sorted().map { "\($0) waits for \(waiting[$0]!)" }.joined(separator: "; ")
        }
    }

    /// Until a step named `name` has started (or ended), as long as `timeout`. Steps said before the wait count: a
    /// step that has already happened does not have to happen again. A track of this process waits as `runner`.
    func wait(for name: String, end: Bool, timeout: Duration, as runner: String? = nil) async throws {
        let phase: Event.Phase = end ? .end : .start
        let deadline = ContinuousClock.now + timeout
        if let runner { lock.withLock { waiting[runner] = name } }
        defer { if let runner { lock.withLock { waiting[runner] = nil } } }
        while !events.contains(where: { $0.name == name && $0.phase == phase }) {
            if let stuck = deadlock() {
                throw ReelError("no track can go on: \(stuck)")
            }
            if ContinuousClock.now > deadline {
                let last = events.last.map {
                    "the last it heard was \($0.reel) line \($0.line)\($0.name.map { " (\($0))" } ?? "") \($0.phase == .start ? "starting" : "ending")"
                } ?? "nothing has been said on it"
                throw ReelError(
                    "waited \(timeout.written) for \(name) \(end ? "to end" : "to start") on the channel; \(last)"
                )
            }
            try await Task.sleep(for: Self.poll)
        }
    }

    /// What a recorder does with `Wait for`: wait on the channel, or say it was skipped when the reel runs alone.
    static func wait(
        _ channel: Channel?, for name: String, end: Bool, timeout: Duration, line: Int, as runner: String? = nil,
        log: (String) -> Void
    ) async throws {
        guard let channel else {
            log("line \(line): skipped Wait for \(name): no other reel runs with this one (\(variable) is not set)")
            return
        }
        try await channel.wait(for: name, end: end, timeout: timeout, as: runner)
    }

    /// The wall clock now, in milliseconds since 1970: what `Event.at` and `Take.startedAt` are in.
    static var now: Int {
        Int((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

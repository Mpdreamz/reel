import Foundation

/// A parsed `.tape`: what to launch, how to capture it, what to do once recording, and where the outputs go.
public struct Tape: Equatable, Sendable {
    public var outputs: [Output]
    public var frameRate: Int
    public var audio: Bool
    public var launch: LaunchTarget
    /// The commands after setup, in order. Recording starts before the first one.
    public var steps: [Step]

    public static let defaultFrameRate = 60
}

public struct Output: Equatable, Sendable {
    public enum Format: String, Equatable, Sendable, CaseIterable {
        case mp4, mov
    }

    public var url: URL
    public var format: Format
}

public enum LaunchTarget: Equatable, Sendable {
    case bundleID(String)
    case app(URL)
}

public struct Step: Equatable, Sendable {
    public var line: Int
    /// The line as written, for the take's timeline.
    public var source: String
    public var command: Command
}

public enum Command: Equatable, Sendable {
    case sleep(Duration)
}

public struct TapeError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// 1-based; nil for problems with the tape as a whole, such as a missing `Output`.
    public var line: Int?
    public var message: String

    public var description: String {
        line.map { "line \($0): \(message)" } ?? message
    }

    public var errorDescription: String? {
        description
    }
}

public extension Tape {
    static func load(_ url: URL) throws -> Tape {
        try parse(String(contentsOf: url, encoding: .utf8), relativeTo: url.deletingLastPathComponent())
    }

    /// Parses a tape. Relative paths (`Output`, `Launch` of an `.app`) resolve against `directory`.
    static func parse(_ text: String, relativeTo directory: URL) throws -> Tape {
        var outputs: [Output] = []
        var frameRate: Int?
        var audio: Bool?
        var launch: (target: LaunchTarget, line: Int)?
        var steps: [Step] = []

        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = index + 1
            let words = try tokenize(String(raw), line: line)
            guard let name = words.first else { continue }
            let args = Array(words.dropFirst())
            let fail = { (message: String) in TapeError(line: line, message: message) }
            let setup = { (command: String) throws in
                if !steps.isEmpty {
                    throw fail("\(command) is setup and must come before the first step (line \(steps[0].line))")
                }
            }

            switch name {
            case "Output":
                try setup(name)
                let path = try single(args, usage: "Output <path>", fail: fail)
                let url = resolve(path, against: directory)
                guard let format = Output.Format(rawValue: url.pathExtension.lowercased()) else {
                    let known = Output.Format.allCases.map { ".\($0.rawValue)" }.joined(separator: " or ")
                    throw fail("unsupported output type '.\(url.pathExtension)'; expected \(known)")
                }
                if outputs.contains(where: { $0.url == url }) {
                    throw fail("\(path) is already an Output")
                }
                outputs.append(Output(url: url, format: format))

            case "Set":
                try setup(name)
                guard args.count == 2 else { throw fail("expected Set <setting> <value>") }
                switch args[0] {
                case "FrameRate":
                    guard let rate = Int(args[1]), (1 ... 120).contains(rate) else {
                        throw fail("FrameRate must be a whole number from 1 to 120, not '\(args[1])'")
                    }
                    frameRate = rate
                case "Audio":
                    switch args[1] {
                    case "on": audio = true
                    case "off": audio = false
                    default: throw fail("Audio must be on or off, not '\(args[1])'")
                    }
                default:
                    throw fail("unknown setting '\(args[0])'; expected FrameRate or Audio")
                }

            case "Launch":
                try setup(name)
                let target = try single(args, usage: "Launch <bundle id or .app path>", fail: fail)
                if let earlier = launch {
                    throw fail("a tape launches one app; line \(earlier.line) already does")
                }
                let isPath = target.hasSuffix(".app") || target.contains("/")
                launch = (isPath ? .app(resolve(target, against: directory)) : .bundleID(target), line)

            case "Sleep":
                let value = try single(args, usage: "Sleep <duration>", fail: fail)
                guard let duration = parseDuration(value) else {
                    throw fail("'\(value)' is not a duration; write 500ms, 2s, 1.5s or a number of seconds")
                }
                steps.append(Step(line: line, source: words.joined(separator: " "), command: .sleep(duration)))

            default:
                let known = ["Output", "Set", "Launch", "Sleep"]
                let hint = known.first { $0.lowercased() == name.lowercased() }.map { "; did you mean \($0)?" }
                throw fail("unknown command '\(name)'" + (hint ?? "; expected one of \(known.joined(separator: ", "))"))
            }
        }

        guard !outputs.isEmpty else { throw TapeError(message: "the tape has no Output") }
        guard let launch else { throw TapeError(message: "the tape has no Launch") }
        return Tape(
            outputs: outputs,
            frameRate: frameRate ?? defaultFrameRate,
            audio: audio ?? true,
            launch: launch.target,
            steps: steps
        )
    }

    /// `500ms`, `2s`, `1.5s`, `1m`, or a bare number of seconds.
    static func parseDuration(_ text: String) -> Duration? {
        let units: [(suffix: String, seconds: Double)] = [("ms", 0.001), ("s", 1), ("m", 60)]
        let (number, scale) = units.first { text.hasSuffix($0.suffix) }
            .map { (String(text.dropLast($0.suffix.count)), $0.seconds) } ?? (text, 1)
        guard let value = Double(number), value >= 0, value.isFinite, number.first?.isNumber == true else {
            return nil
        }
        return .milliseconds(Int64((value * scale * 1000).rounded()))
    }
}

private func single(_ args: [String], usage: String, fail: (String) -> TapeError) throws -> String {
    guard args.count == 1 else { throw fail("expected \(usage)") }
    return args[0]
}

private func resolve(_ path: String, against directory: URL) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expanded, relativeTo: directory).standardizedFileURL
}

/// Splits a line into words: whitespace separates, double quotes group, `#` outside quotes starts a comment.
private func tokenize(_ line: String, line number: Int) throws -> [String] {
    var words: [String] = []
    var current = ""
    var inWord = false
    var quoted = false
    var chars = line.makeIterator()
    while let c = chars.next() {
        if quoted {
            switch c {
            case "\"": quoted = false
            case "\\":
                guard let next = chars.next() else { break }
                current.append(next)
            default: current.append(c)
            }
        } else if c == "\"" {
            quoted = true
            inWord = true
        } else if c == "#", !inWord {
            break
        } else if c.isWhitespace {
            if inWord { words.append(current) }
            current = ""
            inWord = false
        } else {
            current.append(c)
            inWord = true
        }
    }
    if quoted { throw TapeError(line: number, message: "unterminated quote") }
    if inWord { words.append(current) }
    return words
}

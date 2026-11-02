import AVFoundation
import CryptoKit
import Foundation

/// Turns text into an audio file. `fingerprint` names everything that changes how text sounds, so a cached clip is
/// only reused for the same voice.
public protocol Synthesizer: Sendable {
    var fingerprint: String { get }
    /// The extension of what `speak` writes: AVFoundation reads a file by its extension.
    var fileExtension: String { get }
    /// Writes `text` spoken to `url` (a format AVFoundation reads).
    func speak(_ text: String, to url: URL) async throws
}

/// The voiced `Say` lines of a tape, cached in `.reel/<tape>/voice/`: a piece is only voiced when its text, voice and
/// seed have no file yet, so recording again or rendering costs nothing.
public struct Narration: Sendable {
    public struct Line: Sendable, Equatable {
        /// One file per piece of the line, in order; nil for an empty piece.
        public var pieces: [URL?]
        /// The pieces' lengths in seconds.
        public var lengths: [Double]
        public var markers: [String]
        /// Names the voiced line: the take records it, and render refuses a take voiced differently.
        public var key: String
        /// Where each marker falls, when the line was voiced whole (one piece) rather than split at its markers.
        public var offsets: [Double]?

        public var duration: Double {
            lengths.reduce(0, +)
        }

        /// Where each marker falls, in seconds from the start of the line.
        public var markerOffsets: [String: Double] {
            Dictionary(uniqueKeysWithValues: markers.enumerated().map { index, name in
                (name, offsets?[index] ?? lengths[...index].reduce(0, +))
            })
        }
    }

    /// By the line number of each `Say`.
    public var lines: [Int: Line]

    /// - Parameter voicing: false to only use the cache, as render does: a line voiced again may come out a
    ///   different length, and the take was timed to the first.
    public static func prepare(
        _ tape: Tape, into directory: URL, with synthesizer: some Synthesizer, voicing: Bool = true,
        log: (String) -> Void
    ) async throws -> Narration {
        try await prepare(tape, into: directory, voices: { _ in synthesizer }, voicing: voicing, log: log)
    }

    /// - Parameter voices: the synthesizer for a line's named voice, or for the reel's own when nil.
    public static func prepare(
        _ tape: Tape, into directory: URL, voices: (String?) -> any Synthesizer, voicing: Bool = true,
        log: (String) -> Void
    ) async throws -> Narration {
        let folder = directory.appending(path: "voice", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var lines: [Int: Line] = [:]
        var voiced = 0
        for step in tape.steps {
            guard case let .say(speech, _) = step.command else { continue }
            let synthesizer = voices(speech.voice)
            /// The clip of `text`, voiced unless it is cached.
            func clip(_ text: String) async throws -> (url: URL, key: String) {
                let key = digest("\(synthesizer.fingerprint)\n\(text)")
                let url = folder.appending(path: "\(key).\(synthesizer.fileExtension)")
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard voicing else {
                        throw ReelError(
                            "line \(step.line) is not voiced as the take was (its text or the voice changed); "
                                + "record it again"
                        )
                    }
                    log("voicing line \(step.line): \(text)")
                    let partial = folder.appending(path: "\(key).partial.\(synthesizer.fileExtension)")
                    try await synthesizer.speak(text, to: partial)
                    try FileManager.default.moveItem(at: partial, to: url)
                    voiced += 1
                }
                return (url, key)
            }
            var urls: [URL?] = [], lengths: [Double] = [], keys: [String] = []
            for piece in speech.pieces {
                guard !piece.isEmpty else {
                    urls.append(nil)
                    lengths.append(0)
                    keys.append("")
                    continue
                }
                let (url, key) = try await clip(piece)
                urls.append(url)
                try lengths.append(length(of: url))
                keys.append(key)
            }
            var line = Line(
                pieces: urls, lengths: lengths, markers: speech.markers, key: digest(keys.joined(separator: "+"))
            )
            // Voiced in pieces, a line has a seam at each marker. Voiced whole, each marker is found in it: where the
            // speech before it ends (its pieces' speech, the silence a voice pads each clip with at both ends left
            // off, after the whole line's own lead-in), moved to where speech resumes when a pause starts right there.
            if !speech.markers.isEmpty, speech.pieces.count(where: { !$0.isEmpty }) > 1 {
                let (whole, key) = try await clip(speech.text)
                var spoken = try speechSpan(of: whole).start
                var offsets: [Double] = []
                for (piece, url) in zip(speech.pieces, urls).dropLast() {
                    if let url, !piece.isEmpty {
                        let span = try speechSpan(of: url)
                        spoken += span.end - span.start
                    }
                    try offsets.append(resumes(after: spoken, in: whole) ?? spoken)
                }
                line = try Line(
                    pieces: [whole], lengths: [length(of: whole)], markers: speech.markers, key: key, offsets: offsets
                )
            }
            lines[step.line] = line
        }
        if !lines.isEmpty, voiced == 0 { log("narration: \(lines.count) lines, all cached") }
        return Narration(lines: lines)
    }

    /// Read with AVAudioFile: loading an AVURLAsset's duration hung in tests on a clip written moments before.
    static func length(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// How far from where a marker is expected a pause may start and still be the one before its word. A voice runs
    /// some words together; the next pause along can be a word or more later.
    static let pauseReach = 0.12

    /// Loudness every 10 ms of the clip at `url`, and what counts as quiet in it: under an eighth of its loud parts.
    private static func levels(of url: URL) throws -> (levels: [Float], quiet: Float) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return ([], 0)
        }
        try file.read(into: buffer)
        let window = Int(format.sampleRate / 100), frames = Int(buffer.frameLength)
        guard let channel = buffer.floatChannelData?[0], window > 0 else { return ([], 0) }
        let levels = stride(from: 0, to: frames, by: window).map { start in
            let end = min(frames, start + window)
            var sum: Float = 0
            for i in start ..< end {
                sum += channel[i] * channel[i]
            }
            return (sum / Float(end - start)).squareRoot()
        }
        let sorted = levels.sorted()
        let loud = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.9)]
        return (levels, loud / 8)
    }

    /// Where the clip's speech starts and ends, in seconds: the silence a voice pads it with left off.
    static func speechSpan(of url: URL) throws -> (start: Double, end: Double) {
        let (levels, quiet) = try levels(of: url)
        guard let first = levels.firstIndex(where: { $0 >= quiet }),
              let last = levels.lastIndex(where: { $0 >= quiet })
        else { return (0, 0) }
        return (Double(first) / 100, Double(last + 1) / 100)
    }

    /// Where speech resumes after the pause in the clip at `url` that starts nearest `time` (seconds), within
    /// `pauseReach`; nil when there is none. A pause is at least 20 ms quiet.
    static func resumes(after time: Double, in url: URL) throws -> Double? {
        let (levels, quiet) = try levels(of: url)
        var pauses: [(start: Double, end: Double)] = []
        var start: Int?
        for (index, level) in levels.enumerated() {
            if level < quiet {
                if start == nil { start = index }
            } else if let from = start {
                if index - from >= 2 { pauses.append((Double(from) / 100, Double(index) / 100)) }
                start = nil
            }
        }
        let near = pauses.filter { abs($0.start - time) <= pauseReach }
        return near.min { abs($0.start - time) < abs($1.start - time) }?.end
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}

public extension VoiceSettings {
    /// The synthesizer for the voice named `name`, or for `source` when nil. Parsing makes sure the name is set.
    func synthesizer(for name: String? = nil) -> any Synthesizer {
        switch name.flatMap({ named[$0] }) ?? source {
        case let .system(name): SystemVoice(name: name, language: language)
        case let .voicebox(profile): Voicebox(server: server, profile: profile, language: language, seed: seed)
        }
    }
}

/// macOS's own speech synthesizer: no setup, works offline. `name` picks a voice by name (Samantha, Daniel), else the
/// default voice for the language.
public struct SystemVoice: Synthesizer {
    public var name: String?
    public var language: String

    public var fingerprint: String {
        "system \(voice?.identifier ?? language)"
    }

    public var fileExtension: String {
        "caf"
    }

    var voice: AVSpeechSynthesisVoice? {
        if let name {
            return AVSpeechSynthesisVoice.speechVoices().first { $0.name == name }
        }
        return AVSpeechSynthesisVoice(language: language)
    }

    public func speak(_ text: String, to url: URL) async throws {
        if let name, voice == nil {
            throw ReelError("macOS has no voice named \(name); `say -v '?'` lists them")
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let writer = BufferWriter(url: url)
        let synthesizer = AVSpeechSynthesizer()
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            synthesizer.write(utterance) { buffer in
                writer.take(buffer, done: done)
            }
        }
        _ = synthesizer
    }
}

/// Collects a synthesizer's buffers into a file; an empty buffer marks the end.
private final class BufferWriter: @unchecked Sendable {
    let url: URL
    private var file: AVAudioFile?
    private var finished = false
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
    }

    func take(_ buffer: AVAudioBuffer, done: CheckedContinuation<Void, Error>) {
        lock.withLock {
            guard !finished else { return }
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                finished = true
                if file == nil {
                    done.resume(throwing: ReelError("the system voice produced no sound"))
                } else {
                    file = nil
                    done.resume()
                }
                return
            }
            do {
                if file == nil {
                    file = try AVAudioFile(
                        forWriting: url, settings: pcm.format.settings,
                        commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved
                    )
                }
                try file?.write(from: pcm)
            } catch {
                finished = true
                done.resume(throwing: error)
            }
        }
    }
}

/// A voicebox server (https://github.com/jamiepine/voicebox): `profile` is a voice profile's name or id.
public struct Voicebox: Synthesizer {
    public var server: URL
    public var profile: String
    public var language: String
    public var seed: Int
    var session: URLSession = .shared

    public var fingerprint: String {
        "voicebox \(server.absoluteString) \(profile) \(language) \(seed)"
    }

    public var fileExtension: String {
        "wav"
    }

    public func speak(_ text: String, to url: URL) async throws {
        let voice = try await lookUp()
        var request = URLRequest(url: server.appending(path: "generate/stream"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["profile_id": voice.id, "text": text, "language": language, "seed": seed]
        // The profile's own engine: voicebox otherwise uses its default, which a preset voice may not support
        // ("Preset profile … only supports engine 'kokoro', not 'qwen'").
        if let engine = voice.engine { body["engine"] = engine }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ReelError("voicebox could not voice '\(text)': \(String(decoding: data.prefix(300), as: UTF8.self))")
        }
        try data.write(to: url)
    }

    /// The id of the profile named `profile`, or `profile` itself when it is an id.
    func profileID() async throws -> String {
        try await lookUp().id
    }

    /// The profile named `profile`, or whose id it is.
    private func lookUp() async throws -> Profile {
        let (data, response) = try await send(URLRequest(url: server.appending(path: "profiles")))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let profiles = try? JSONDecoder().decode([Profile].self, from: data)
        else {
            throw ReelError("voicebox at \(server.absoluteString) did not list its voice profiles")
        }
        if let match = profiles.first(where: { $0.id == profile || $0.name == profile }) { return match }
        let names = profiles.map(\.name).joined(separator: ", ")
        throw ReelError("voicebox has no profile '\(profile)'; it has \(names.isEmpty ? "none" : names)")
    }

    private struct Profile: Decodable {
        var id: String
        var name: String
        /// The engine the profile speaks with; absent from voicebox versions without engines.
        var engine: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case engine = "default_engine"
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw ReelError(
                "cannot reach voicebox at \(server.absoluteString) (\(error.localizedDescription)); start it and "
                    + "enable its API server, or Set VoiceServer"
            )
        }
    }
}

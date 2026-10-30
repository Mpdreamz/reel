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

        public var duration: Double {
            lengths.reduce(0, +)
        }

        /// Where each marker falls, in seconds from the start of the line.
        public var markerOffsets: [String: Double] {
            Dictionary(uniqueKeysWithValues: markers.enumerated().map { index, name in
                (name, lengths[...index].reduce(0, +))
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
        let folder = directory.appending(path: "voice", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var lines: [Int: Line] = [:]
        var voiced = 0
        for step in tape.steps {
            guard case let .say(speech, _) = step.command else { continue }
            var urls: [URL?] = [], lengths: [Double] = [], keys: [String] = []
            for piece in speech.pieces {
                guard !piece.isEmpty else {
                    urls.append(nil)
                    lengths.append(0)
                    keys.append("")
                    continue
                }
                let key = digest("\(synthesizer.fingerprint)\n\(piece)")
                let url = folder.appending(path: "\(key).\(synthesizer.fileExtension)")
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard voicing else {
                        throw ReelError(
                            "line \(step.line) is not voiced as the take was (its text or the voice changed); "
                                + "record it again"
                        )
                    }
                    log("voicing line \(step.line): \(piece)")
                    let partial = folder.appending(path: "\(key).partial.\(synthesizer.fileExtension)")
                    try await synthesizer.speak(piece, to: partial)
                    try FileManager.default.moveItem(at: partial, to: url)
                    voiced += 1
                }
                urls.append(url)
                try lengths.append(length(of: url))
                keys.append(key)
            }
            lines[step.line] = Line(
                pieces: urls, lengths: lengths, markers: speech.markers, key: digest(keys.joined(separator: "+"))
            )
        }
        if !lines.isEmpty, voiced == 0 { log("narration: \(lines.count) lines, all cached") }
        return Narration(lines: lines)
    }

    /// Read with AVAudioFile: loading an AVURLAsset's duration hung in tests on a clip written moments before.
    static func length(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
    }
}

public extension VoiceSettings {
    /// The synthesizer for `source`.
    func synthesizer() -> any Synthesizer {
        switch source {
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

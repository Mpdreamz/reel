import Foundation

/// A `Say` line: its text cut at `[markers]`. Each piece is voiced on its own, so a marker's time is the length of
/// the pieces before it, exactly.
public struct Speech: Equatable, Sendable {
    /// One more than `markers`: the text before the first marker, between each two, and after the last. A piece can
    /// be empty (a marker at the start).
    public var pieces: [String]
    public var markers: [String]

    /// The words as a subtitle shows them: no markers, single spaces.
    public var text: String {
        pieces.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    init(_ source: String, fail: (String) -> TapeError) throws {
        pieces = []
        markers = []
        var rest = source[...]
        while let open = rest.firstIndex(of: "[") {
            guard let close = rest[open...].firstIndex(of: "]") else { throw fail("a [ in the text has no ]") }
            let name = String(rest[rest.index(after: open) ..< close])
            guard let first = name.first, first.isLetter || first.isNumber,
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            else {
                throw fail("'[\(name)]' is not a marker; name it with letters, digits, - and _, such as [play]")
            }
            pieces.append(rest[..<open].trimmingCharacters(in: .whitespaces))
            markers.append(name)
            rest = rest[rest.index(after: close)...]
        }
        pieces.append(rest.trimmingCharacters(in: .whitespaces))
        if text.isEmpty { throw fail("Say needs words to speak") }
    }
}

/// Who speaks: macOS's own synthesizer (`system`, `system:Samantha`) or a voicebox profile (`voicebox:narrator`,
/// by name or id).
public enum VoiceSource: Equatable, Sendable, CustomStringConvertible {
    case system(String?)
    case voicebox(String)

    init(_ value: String, fail: (String) -> TapeError) throws {
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count) {
        case ("system", 1): self = .system(nil)
        case ("system", 2) where !parts[1].isEmpty: self = .system(parts[1])
        case ("voicebox", 2) where !parts[1].isEmpty: self = .voicebox(parts[1])
        default:
            throw fail("Voice must be system, system:<voice name> or voicebox:<profile>, not '\(value)'")
        }
    }

    public var description: String {
        switch self {
        case .system(nil): "system"
        case let .system(name?): "system:\(name)"
        case let .voicebox(profile): "voicebox:\(profile)"
        }
    }
}

public struct VoiceSettings: Equatable, Sendable {
    public var source = VoiceSource.system(nil)
    /// voicebox's own default address.
    public var server = URL(string: "http://127.0.0.1:17493")!
    /// The same seed voices the same text the same way, so a take can be recorded again.
    public var seed = 1
    public var language = "en"
    /// The app's sound under narration, as a fraction of `appVolume`.
    public var ducking = 0.25
    public var voiceVolume = 1.0
    public var appVolume = 1.0
    /// Show each `Say` as a caption while it plays.
    public var subtitles = false

    public init() {}
}

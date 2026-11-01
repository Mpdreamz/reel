import Foundation

/// A named set of render settings for where a video is going: `Set Profiles github, social` renders every Output once
/// for each, as `name-github.mp4` and `name-social.mp4`. A profile's settings apply after the tape's own, so a plain
/// `Set` never cancels one. It only sets what render decides: the take is recorded once, whatever the profiles.
public struct Profile: Equatable, Sendable {
    public var name: String
    /// What it is for, in a few words.
    public var purpose: String
    /// Its `Set` lines, in order: setting and value.
    public var settings: [Setting]

    public struct Setting: Equatable, Sendable {
        public var name: String
        public var value: String
        /// What a path in the value is relative to: the file it was written in.
        public var directory: URL?
        /// Where it was written, for errors: `house.reelpreset line 7`; nil for a built-in.
        public var origin: String?

        public init(_ name: String, _ value: String, directory: URL? = nil, origin: String? = nil) {
            self.name = name
            self.value = value
            self.directory = directory
            self.origin = origin
        }
    }

    /// Settings a profile cannot change: they are fixed when recording, and one take serves every profile.
    static let recordingSettings: Set<String> = [
        "FrameRate", "Audio", "Size", "TypingSpeed", "WaitTimeout", "Voice", "VoiceServer", "VoiceSeed",
        "VoiceLanguage", "Browser", "Viewport", "FontSize", "Columns", "Rows", "WorkingDirectory", "Theme",
        "Redact", "Title",
    ]

    /// Names an Output's type takes, kept for conditions on it.
    static let reservedNames: Set<String> = ["mp4", "mov", "gif"]

    /// `Profile docs extends web "Our docs site"`, and its indented `Set` lines: one written in a tape or a preset.
    struct Definition: Equatable, Sendable {
        var name: String
        var extends: String?
        var purpose: String?
        var settings: [Setting]
        var origin: String
    }

    /// The built-in profiles with `definitions` applied in order: one with a known name amends it (its settings after
    /// the profile's own), a new one starts from the profile it extends, or from nothing.
    static func resolve(_ definitions: [Definition]) throws -> [Profile] {
        var known = builtIn
        for definition in definitions {
            let fail = { (message: String) in TapeError(message: "\(definition.origin): \(message)") }
            if let index = known.firstIndex(where: { $0.name == definition.name }) {
                guard definition.extends == nil else {
                    throw fail(
                        "there is already a profile \(definition.name); amend it with Profile \(definition.name), "
                            + "or give the new one a name of its own"
                    )
                }
                known[index].settings += definition.settings
                if let purpose = definition.purpose { known[index].purpose = purpose }
            } else {
                var settings: [Setting] = []
                if let base = definition.extends {
                    guard let extended = known.first(where: { $0.name == base }) else {
                        throw fail("there is no profile \(base) to extend; there are \(names(known))")
                    }
                    settings = extended.settings
                }
                known.append(Profile(
                    name: definition.name, purpose: definition.purpose ?? "defined at \(definition.origin)",
                    settings: settings + definition.settings
                ))
            }
        }
        return known
    }

    public init(name: String, purpose: String, settings: [Setting]) {
        self.name = name
        self.purpose = purpose
        self.settings = settings
    }

    /// `musicbox.mp4` as this profile writes it: `musicbox-github.mp4`.
    public func suffixed(_ url: URL) -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appending(path: "\(base)-\(name).\(ext)")
    }

    /// The profiles reel knows. The social ones frame on the exact sizes the platforms show. Platform limits are the
    /// strictest common ones, from third-party guides where the platform publishes none: GitHub's 10 MB for an
    /// attached video or GIF is its own; Mastodon's 40 MB default, X's 2:20 for standard accounts and TikTok's 287 MB
    /// on mobile are not.
    public static let builtIn: [Profile] = [
        Profile(name: "highest", purpose: "archiving and editing later", settings: [
            Setting("Codec", "prores"), Setting("Quality", "100"),
            Setting("GifWidth", "4000"), Setting("GifFrameRate", "30"), Setting("GifColors", "256"),
        ]),
        Profile(name: "github", purpose: "READMEs, issues and pull requests", settings: [
            Setting("VideoWidth", "1920"), Setting("MaxSize", "10MB"), Setting("GifWidth", "800"),
        ]),
        Profile(name: "web", purpose: "landing pages and docs sites", settings: [
            Setting("VideoWidth", "1920"), Setting("Quality", "60"), Setting("VideoFrameRate", "30"),
        ]),
        Profile(name: "social", purpose: "YouTube Shorts, TikTok and Reels", settings: [
            Setting("Shape", "1080x1920"), Setting("Quality", "70"),
            Setting("VideoFrameRate", "30"), Setting("MaxSize", "250MB"), Setting("MaxLength", "3m"),
            Setting("Subtitles", "on"), Setting("Formats", "mp4, mov"),
        ]),
        Profile(name: "feed", purpose: "X, Bluesky, Mastodon and LinkedIn", settings: [
            Setting("Shape", "1920x1080"), Setting("VideoFrameRate", "30"),
            Setting("MaxSize", "40MB"), Setting("MaxLength", "140s"), Setting("Subtitles", "on"),
            Setting("Formats", "mp4, mov"),
        ]),
        Profile(name: "square", purpose: "Instagram and LinkedIn feeds", settings: [
            Setting("Shape", "1080x1080"), Setting("VideoFrameRate", "30"),
            Setting("MaxSize", "40MB"), Setting("MaxLength", "140s"), Setting("Subtitles", "on"),
            Setting("Formats", "mp4, mov"),
        ]),
    ]

    public static func named(_ name: String) -> Profile? {
        builtIn.first { $0.name == name }
    }

    /// `github, social or square`
    static func names(_ profiles: [Profile] = builtIn) -> String {
        let all = profiles.map(\.name)
        return all.dropLast().joined(separator: ", ") + " or " + all.last!
    }
}

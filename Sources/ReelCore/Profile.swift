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

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
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
    /// strictest common ones, from third-party guides where the
    /// platform publishes none: GitHub's 10 MB for an attached video or GIF is its own; Mastodon's 40 MB default,
    /// X's 2:20 for standard accounts and TikTok's 287 MB on mobile are not.
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
    static var names: String {
        let all = builtIn.map(\.name)
        return all.dropLast().joined(separator: ", ") + " or " + all.last!
    }
}

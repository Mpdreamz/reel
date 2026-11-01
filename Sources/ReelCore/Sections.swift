import CoreGraphics
import Foundation

/// A title card before or after the demo (`Intro`, `Outro`): a title, maybe a subtitle, over a background, and how
/// it moves into what follows it (an intro) or what comes before it moves into it (an outro).
public struct Section: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    /// Seconds on screen, the transition included; nil for the background video's own length, else `defaultLength`.
    public var duration: Duration?
    public var background: Background
    public var transition: SectionTransition

    public static let defaultLength = Duration.seconds(3)

    /// Whether it says anything: a section with neither title nor subtitle is only its background.
    var hasTitles: Bool {
        !title.isEmpty || !(subtitle ?? "").isEmpty
    }

    init(
        title: String, subtitle: String?, duration: Duration?, background: Background = .standard,
        transition: SectionTransition
    ) {
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
        self.background = background
        self.transition = transition
    }
}

/// What a section shows behind its title: a colour, an image, or a video, whose sound plays with it.
public enum Background: Equatable, Sendable {
    /// Red, green and blue, 0 to 1.
    case color(Double, Double, Double)
    case image(URL)
    case video(URL)

    public static let standard = Background.color(0.07, 0.07, 0.08)

    /// `#1d2b3a`, an image (`.png`, `.jpg`, `.jpeg`, `.heic`) or a video (`.mov`, `.mp4`, `.m4v`), relative to the
    /// tape.
    init(_ value: String, resolve: (String) throws -> URL, fail: (String) -> TapeError) throws {
        if value.hasPrefix("#") {
            let hex = value.dropFirst()
            guard hex.count == 6, let number = UInt32(hex, radix: 16) else {
                throw fail("'\(value)' is not a colour; write #rrggbb, such as #1d2b3a")
            }
            self = .color(
                Double((number >> 16) & 0xFF) / 255, Double((number >> 8) & 0xFF) / 255, Double(number & 0xFF) / 255
            )
            return
        }
        let url = try resolve(value)
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic": self = .image(url)
        case "mov", "mp4", "m4v": self = .video(url)
        default:
            throw fail("a background is #rrggbb, an image (.png, .jpg, .heic) or a video (.mov, .mp4), not '\(value)'")
        }
    }
}

public enum TransitionKind: String, Equatable, Sendable, CaseIterable {
    /// One section dissolves into the next.
    case crossfade
    /// Through black: out, then in.
    case fade
    /// The next section pushes the one before out, moving left (the next comes in from the right), and so on.
    case slideLeft = "slide-left", slideRight = "slide-right", slideUp = "slide-up", slideDown = "slide-down"
    /// The section on top grows and fades away, or shrinks into place as it fades in.
    case zoom
    /// An edge crosses the frame, moving left (revealing from the right), and so on.
    case wipeLeft = "wipe-left", wipeRight = "wipe-right", wipeUp = "wipe-up", wipeDown = "wipe-down"
    /// No transition.
    case cut

    /// Whether the two sections overlap while it plays: fade goes through black instead, cut does not play.
    var overlaps: Bool {
        self != .fade && self != .cut
    }
}

/// `Intro@slide-left,ease-out,800ms`: a kind, an easing and a duration, in any order, each optional.
public struct SectionTransition: Equatable, Sendable {
    public var kind: TransitionKind
    public var easing: Easing
    public var duration: Duration

    public static let standard = SectionTransition(kind: .crossfade, easing: .easeInOut, duration: .milliseconds(600))

    public init(kind: TransitionKind, easing: Easing, duration: Duration) {
        self.kind = kind
        self.easing = easing
        self.duration = duration
    }

    init(_ option: String, fail: (String) -> TapeError) throws {
        var kind: TransitionKind?, easing: Easing?, duration: Duration?
        for part in option.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            if kind == nil, let found = TransitionKind(rawValue: part) {
                kind = found
            } else if easing == nil, let found = Easing(rawValue: part) {
                easing = found
            } else if duration == nil, let found = Tape.parseDuration(part) {
                duration = found
            } else {
                let kinds = TransitionKind.allCases.map(\.rawValue).joined(separator: ", ")
                throw fail("'@\(option)' is not a transition; write a kind (\(kinds)), an easing and a duration, "
                    + "such as @slide-left,ease-out,800ms")
            }
        }
        self.kind = kind ?? Self.standard.kind
        self.easing = easing ?? Self.standard.easing
        self.duration = kind == .cut ? .zero : duration ?? Self.standard.duration
    }

    var seconds: Double {
        duration.seconds
    }
}

/// How one section looks at a moment of a transition: its opacity, how far it has moved and grown, and how much of
/// it shows. Offsets are fractions of the frame (x right, y down), the crop is a fraction of it.
public struct Look: Equatable, Sendable {
    public var opacity = 1.0
    public var offset = CGPoint.zero
    public var scale = 1.0
    /// The part of the frame that shows, as fractions: (0, 0, 1, 1) is all of it.
    public var crop = CGRect(x: 0, y: 0, width: 1, height: 1)

    public static let still = Look()

    /// How the section going out (`outgoing`) or coming in looks at `progress` 0…1 (eased already). `onTop` says
    /// whether
    /// it is drawn over the other: only the section on top fades, zooms or is wiped, revealing the one beneath.
    public static func of(
        _ kind: TransitionKind, progress p: Double, outgoing: Bool, onTop: Bool
    ) -> Look {
        var look = Look()
        switch kind {
        case .cut:
            look.opacity = outgoing ? (p < 1 ? 1 : 0) : (p > 0 ? 1 : 0)
        case .fade:
            // Out over the first half, in over the second, through black.
            look.opacity = outgoing ? max(0, 1 - 2 * p) : max(0, 2 * p - 1)
        case .crossfade:
            if onTop { look.opacity = outgoing ? 1 - p : p }
        case .slideLeft, .slideRight, .slideUp, .slideDown:
            let direction = switch kind {
            case .slideLeft: CGPoint(x: -1, y: 0)
            case .slideRight: CGPoint(x: 1, y: 0)
            case .slideUp: CGPoint(x: 0, y: -1)
            default: CGPoint(x: 0, y: 1)
            }
            // The one going out moves off the way the slide goes; the one coming in arrives from the other side.
            let travelled = outgoing ? p : p - 1
            look.offset = CGPoint(x: direction.x * travelled, y: direction.y * travelled)
        case .zoom:
            if onTop {
                look.opacity = outgoing ? 1 - p : p
                look.scale = outgoing ? 1 + 0.3 * p : 1.3 - 0.3 * p
            }
        case .wipeLeft, .wipeRight, .wipeUp, .wipeDown:
            guard onTop else { break }
            // What of the section on top still shows: it shrinks away as one goes out and grows as one comes in.
            let shown = outgoing ? 1 - p : p
            // Wiping left or up, the part going out keeps its leading side and the part coming in grows from the far
            // side; right and down mirror that.
            let fromLeading = (kind == .wipeLeft || kind == .wipeUp) == outgoing
            let start = fromLeading ? 0 : 1 - shown
            let horizontal = kind == .wipeLeft || kind == .wipeRight
            look.crop = horizontal
                ? CGRect(x: start, y: 0, width: shown, height: 1)
                : CGRect(x: 0, y: start, width: 1, height: shown)
        }
        return look
    }
}

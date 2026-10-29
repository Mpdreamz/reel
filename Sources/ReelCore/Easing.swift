import Foundation

/// How a change moves from where it was to where it goes, over `progress` 0…1.
public enum Easing: String, Equatable, Sendable, CaseIterable {
    case linear
    case easeIn = "ease-in"
    case easeOut = "ease-out"
    case easeInOut = "ease-in-out"
    /// Gentler than ease-in-out: half a sine wave.
    case smooth
    /// No movement: the change happens at once.
    case snap

    public func callAsFunction(_ progress: Double) -> Double {
        let t = min(1, max(0, progress))
        switch self {
        case .linear: return t
        case .easeIn: return t * t * t
        case .easeOut: return 1 - pow(1 - t, 3)
        case .easeInOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .smooth: return (1 - cos(.pi * t)) / 2
        case .snap: return 1
        }
    }

    static func problem(_ value: String) -> String {
        "'\(value)' is not an easing; expected " + allCases.map(\.rawValue).joined(separator: ", ")
    }
}

/// An easing and how long it takes: `Zoom@ease-out`, `Zoom@600ms`, `Zoom@ease-in,800ms`. A part left out (nil) is the
/// tape's (`Set ZoomEasing`, `Set ZoomDuration`).
public struct Transition: Equatable, Sendable {
    public var easing: Easing?
    public var duration: Duration?

    public static let standard = Transition(easing: .easeInOut, duration: .milliseconds(400))

    public init(easing: Easing?, duration: Duration?) {
        self.easing = easing
        self.duration = duration
    }

    /// The parts after `@`, comma separated: an easing, a duration, or both in either order.
    init(_ option: String, fail: (String) -> TapeError) throws {
        for part in option.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
            if easing == nil, let curve = Easing(rawValue: part) {
                easing = curve
            } else if duration == nil, let time = Tape.parseDuration(part) {
                duration = time
            } else {
                throw fail(
                    "'@\(option)' is not a transition; write an easing, a duration or both, such as @ease-out,600ms"
                )
            }
        }
    }

    /// This transition, with `fallback`'s parts where it has none; in seconds.
    public func over(_ fallback: Transition) -> (easing: Easing, seconds: Double) {
        (easing ?? fallback.easing ?? .easeInOut, (duration ?? fallback.duration ?? .zero).seconds)
    }
}

import CoreGraphics

/// Something drawn over the take at render time, in seconds from its first frame.
public struct Overlay: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case caption(String)
        /// A key badge: `⌘S`, `↓ ×3`.
        case keys(String)
        /// Where a click landed, in points from the window's top left.
        case ripple(CGPoint)
    }

    public var kind: Kind
    public var start: Double
    public var end: Double
}

public enum OverlayPlan {
    /// How long a key badge stays after its key is released.
    static let badgeLinger = 0.6
    static let rippleDuration = 0.5
    /// The click is the last thing a `Click` step does; its press starts about this long before the step ends.
    static let pressLead = 0.06

    /// What to draw over `take`, from the tape as it is now. Captions anchor to the end of the action before them,
    /// so they can change freely; the actions themselves must be the ones the take recorded.
    public static func make(tape: Tape, take: Take) throws -> [Overlay] {
        let actions = tape.actions
        guard actions.count == take.events.count else {
            throw ReelError(
                "the tape has \(actions.count) actions but the take recorded \(take.events.count); record it again"
            )
        }
        for (step, event) in zip(actions, take.events) where step.source != event.command {
            throw ReelError(
                "line \(step.line) is '\(step.source)' but the take recorded '\(event.command)'; "
                    + "record it again (captions can change without one, actions cannot)"
            )
        }
        let end = Double(take.durationMs) / 1000
        var overlays: [Overlay] = []

        // Captions, each from the end of the action before it.
        var done = 0
        var open: (text: String, start: Double, until: Double)?
        func close(at time: Double) {
            if let current = open, min(time, current.until) > current.start {
                overlays.append(Overlay(
                    kind: .caption(current.text),
                    start: current.start,
                    end: min(time, current.until)
                ))
            }
            open = nil
        }
        for step in tape.steps {
            guard case let .caption(text, duration) = step.command else {
                done += 1
                continue
            }
            let at = done == 0 ? 0 : Double(take.events[done - 1].endMs) / 1000
            close(at: at)
            if let text {
                open = (text, at, duration.map { at + $0.seconds } ?? end)
            }
        }
        close(at: end)

        for (step, event) in zip(actions, take.events) {
            let start = Double(event.startMs) / 1000, stop = Double(event.endMs) / 1000
            switch step.command {
            case let .key(combo, count) where tape.keyBadges:
                let label = count > 1 ? "\(combo.symbol) ×\(count)" : combo.symbol
                overlays.append(Overlay(kind: .keys(label), start: start, end: min(end, stop + badgeLinger)))
            case .click where tape.clickRipples:
                guard let x = event.x, let y = event.y else { continue }
                let pressed = max(0, stop - pressLead)
                overlays.append(Overlay(
                    kind: .ripple(CGPoint(x: x, y: y)), start: pressed, end: min(end, pressed + rippleDuration)
                ))
            default:
                break
            }
        }
        return overlays.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

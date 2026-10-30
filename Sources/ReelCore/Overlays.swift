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
                "the reel has \(actions.count) actions but the take recorded \(take.events.count); record it again"
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
        for (step, at) in zip(tape.steps, Anchors.times(tape: tape, take: take)) {
            guard case let .caption(text, duration) = step.command else { continue }
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

public extension OverlayPlan {
    /// The overlays in the output's time, and each ripple where its click shows under the zoom. One that falls in a
    /// stretch left out is dropped.
    static func mapped(_ overlays: [Overlay], through edit: Edit, zoom: ZoomPlan?) -> [Overlay] {
        overlays.compactMap { overlay in
            var moved = overlay
            moved.start = edit.map(overlay.start)
            moved.end = edit.map(overlay.end)
            guard moved.end - moved.start > 0.05 else { return nil }
            if case let .ripple(point) = overlay.kind, let zoom {
                moved.kind = .ripple(zoom.project(point, through: zoom.region(at: overlay.start)))
            }
            return moved
        }
    }

    /// Each narrated line as a caption while it plays. A subtitle takes the caption's place: a `Caption` showing at the
    /// same time is cut around it.
    static func adding(subtitles clips: [Soundtrack.Clip], to overlays: [Overlay]) -> [Overlay] {
        let spoken = clips.filter { $0.end > $0.start }.map { ($0.start, $0.end) }
        var result: [Overlay] = []
        for overlay in overlays {
            guard case .caption = overlay.kind else {
                result.append(overlay)
                continue
            }
            // What is left of the caption around every line.
            var pieces = [(overlay.start, overlay.end)]
            for (start, end) in spoken {
                pieces = pieces.flatMap { piece -> [(Double, Double)] in
                    guard start < piece.1, end > piece.0 else { return [piece] }
                    return [(piece.0, start), (end, piece.1)].filter { $0.1 - $0.0 > 0.05 }
                }
            }
            result += pieces.map { Overlay(kind: overlay.kind, start: $0.0, end: $0.1) }
        }
        result += clips.filter { $0.end > $0.start }
            .map { Overlay(kind: .caption($0.text), start: $0.start, end: $0.end) }
        return result.sorted { $0.start < $1.start }
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

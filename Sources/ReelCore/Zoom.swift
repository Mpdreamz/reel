import CoreGraphics

/// What part of the window shows at any moment, in points from its top left: the whole window, or a region of the
/// window's shape zoomed in on, easing from one to the next.
public struct ZoomPlan: Sendable {
    /// How long a zoom takes to ease in or out.
    static let ease = 0.4
    /// Room around a fitted element, as a share of its size.
    static let padding = 0.08
    /// The most a fitted element is zoomed; an explicit scale may go further.
    static let fitLimit = 4.0
    static let defaultScale = 2.0

    /// The window, in points.
    public var window: CGSize
    /// Each zoom from when it starts: where it frames over time from then on.
    var states: [(start: Double, frame: @Sendable (Double) -> CGRect)]
    /// What render should say about the zooms: a fitted element that is nearly the window's size barely zooms.
    public var notes: [String] = []

    public static func full(_ window: CGSize) -> ZoomPlan {
        ZoomPlan(window: window, states: [])
    }

    public static func make(tape: Tape, take: Take) -> ZoomPlan {
        let window = CGSize(width: Double(take.width) / take.scale, height: Double(take.height) / take.scale)
        let anchors = Anchors.times(tape: tape, take: take)
        var plan = ZoomPlan(window: window, states: [])
        let full = CGRect(origin: .zero, size: window)
        var done = 0
        for (step, at) in zip(tape.steps, anchors) {
            let event = step.command.isRenderOnly ? nil : take.events[safe: done]
            if !step.command.isRenderOnly { done += 1 }
            guard case let .zoom(target, scale) = step.command else { continue }
            switch target {
            case .off:
                plan.states.append((at, { _ in full }))
            case let .point(point):
                let region = plan.region(around: point, scale: scale ?? defaultScale)
                plan.states.append((at, { _ in region }))
            case .cursor:
                let samples = take.cursor ?? []
                let scale = scale ?? defaultScale
                plan.states.append((at, { [plan] time in
                    plan.region(
                        around: smoothed(samples, at: time) ?? CGPoint(x: full.midX, y: full.midY),
                        scale: scale
                    )
                }))
            case .element:
                guard let event, let x = event.x, let y = event.y else { continue }
                let first = CGRect(x: x, y: y, width: event.w ?? 0, height: event.h ?? 0)
                if scale == nil, window.width / plan.fit(first).width < 1.2 {
                    plan.notes.append(
                        "line \(step.line): the element nearly fills the window, so fitting it barely zooms; "
                            + "give a scale, such as \(step.source) 2x"
                    )
                }
                // The element's frame as sampled after each step since, so the zoom follows it.
                let track = [Take.Sample(ms: event.endMs, frame: first)]
                    + (take.focus ?? []).filter { $0.ms > event.endMs }
                plan.states.append((at, { [plan] time in
                    let frame = track.last(where: { Double($0.ms) / 1000 <= time })?.rect ?? first
                    return scale.map { plan.region(around: CGPoint(x: frame.midX, y: frame.midY), scale: $0) }
                        ?? plan.fit(frame)
                }))
            }
        }
        return plan
    }

    /// What shows at `time`, easing from the zoom before.
    public func region(at time: Double) -> CGRect {
        let full = CGRect(origin: .zero, size: window)
        guard let index = states.lastIndex(where: { $0.start <= time }) else { return full }
        let current = states[index]
        let target = current.frame(time)
        let progress = (time - current.start) / Self.ease
        guard progress < 1 else { return target }
        // From wherever the zoom before had got to when this one started.
        let before = index > 0 ? region(at: current.start - 1e-6) : full
        let t = progress < 0.5 ? 4 * progress * progress * progress : 1 - pow(-2 * progress + 2, 3) / 2
        return CGRect(
            x: before.minX + (target.minX - before.minX) * t, y: before.minY + (target.minY - before.minY) * t,
            width: before.width + (target.width - before.width) * t,
            height: before.height + (target.height - before.height) * t
        )
    }

    /// A region of the window's shape, `scale` times smaller, centred on `point` as far as the window allows.
    func region(around point: CGPoint, scale: Double) -> CGRect {
        let size = CGSize(width: window.width / scale, height: window.height / scale)
        return clamped(CGRect(
            x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height
        ))
    }

    /// The smallest region of the window's shape that shows `frame` with some room, zoomed at most `fitLimit`.
    func fit(_ frame: CGRect) -> CGRect {
        let padded = frame.insetBy(dx: -frame.width * Self.padding, dy: -frame.height * Self.padding)
        let scale = min(window.width / max(padded.width, 1), window.height / max(padded.height, 1))
        return region(around: CGPoint(x: frame.midX, y: frame.midY), scale: max(1, min(scale, Self.fitLimit)))
    }

    private func clamped(_ region: CGRect) -> CGRect {
        CGRect(
            x: min(max(0, region.minX), window.width - region.width),
            y: min(max(0, region.minY), window.height - region.height),
            width: region.width, height: region.height
        )
    }

    /// Maps a point of the window to where it shows in the frame when `region` fills it.
    public func project(_ point: CGPoint, through region: CGRect) -> CGPoint {
        let scale = window.width / region.width
        return CGPoint(x: (point.x - region.minX) * scale, y: (point.y - region.minY) * scale)
    }
}

/// The cursor at `time`, averaged over the 0.3 s around it so a following zoom glides rather than jitters.
private func smoothed(_ samples: [Take.Sample], at time: Double) -> CGPoint? {
    let near = samples.filter { abs(Double($0.ms) / 1000 - time) <= 0.15 }
    guard !near.isEmpty else {
        return samples.last(where: { Double($0.ms) / 1000 <= time }).map { CGPoint(x: $0.x, y: $0.y) }
    }
    let count = Double(near.count)
    return CGPoint(x: near.map(\.x).reduce(0, +) / count, y: near.map(\.y).reduce(0, +) / count)
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import Foundation

/// When each step of a tape happens in its take, in seconds from the first frame: an action at its event's start, and
/// a render-only step (a caption, a zoom, a speed, a trim) at the end of the action before it.
public enum Anchors {
    public static func times(tape: Tape, take: Take) -> [Double] {
        var done = 0
        return tape.steps.map { step in
            if !step.command.isRenderOnly {
                defer { done += 1 }
                return done < take.events.count ? Double(take.events[done].startMs) / 1000 : 0
            }
            return done == 0 ? 0 : Double(take.events[min(done, take.events.count) - 1].endMs) / 1000
        }
    }
}

/// How the take's time becomes the output's: stretches left out (`Hide` … `Show`) and stretches sped up (`Speed 4x` …
/// `Speed off`), narrated lines kept at their own pace.
public struct Edit: Codable, Equatable, Sendable {
    /// What is kept of the take, in order: each source stretch and how fast it plays.
    public struct Segment: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var rate: Double

        public var outputLength: Double {
            (end - start) / rate
        }
    }

    public var segments: [Segment]

    public static func whole(_ duration: Double) -> Edit {
        Edit(segments: [Segment(start: 0, end: duration, rate: 1)])
    }

    /// - Parameter spoken: the narrated stretches, which are never sped up and never hidden.
    public static func make(tape: Tape, take: Take, spoken: [ClosedRange<Double>] = []) throws -> Edit {
        let end = Double(take.durationMs) / 1000
        let anchors = Anchors.times(tape: tape, take: take)
        var hidden: [(start: Double, end: Double, line: Int)] = []
        var fast: [(start: Double, end: Double, rate: Double)] = []
        var openHide: (time: Double, line: Int)?
        var openSpeed: (time: Double, rate: Double)?
        for (step, at) in zip(tape.steps, anchors) {
            switch step.command {
            case let .hide(on):
                if on { openHide = (at, step.line) } else if let open = openHide {
                    hidden.append((open.time, at, open.line))
                    openHide = nil
                }
            case let .speed(rate):
                if let open = openSpeed { fast.append((open.time, at, open.rate)) }
                openSpeed = rate.map { (at, $0) }
            default:
                break
            }
        }
        if let open = openHide { hidden.append((open.time, end, open.line)) }
        if let open = openSpeed { fast.append((open.time, end, open.rate)) }

        for cut in hidden {
            if let line = spoken.first(where: { $0.lowerBound < cut.end && $0.upperBound > cut.start }) {
                throw ReelError(
                    String(
                        format: "the Hide on line %d would cut narration (%.1f s to %.1f s); move it",
                        cut.line,
                        line.lowerBound,
                        line.upperBound
                    )
                )
            }
        }

        // Every moment something changes, then each stretch between two of them as hidden, or at its rate.
        var cuts = Set([0, end])
        for range in hidden {
            cuts.formUnion([range.start, range.end])
        }
        for range in fast {
            cuts.formUnion([range.start, range.end])
        }
        for range in spoken {
            cuts.formUnion([range.lowerBound, range.upperBound])
        }
        let points = cuts.filter { $0 >= 0 && $0 <= end }.sorted()
        var segments: [Segment] = []
        for (a, b) in zip(points, points.dropFirst()) where b > a {
            let middle = (a + b) / 2
            if hidden.contains(where: { $0.start <= middle && middle < $0.end }) { continue }
            let speaking = spoken.contains { $0.lowerBound <= middle && middle < $0.upperBound }
            let rate = speaking ? 1 : fast.last(where: { $0.start <= middle && middle < $0.end })?.rate ?? 1
            if let last = segments.last, last.end == a, last.rate == rate {
                segments[segments.count - 1].end = b
            } else {
                segments.append(Segment(start: a, end: b, rate: rate))
            }
        }
        return Edit(segments: segments)
    }

    public var duration: Double {
        segments.reduce(0) { $0 + $1.outputLength }
    }

    public var isIdentity: Bool {
        segments.count == 1 && segments[0].start == 0 && segments[0].rate == 1
    }

    /// Where a moment of the take lands in the output. A moment left out lands where the output picks up again.
    public func map(_ time: Double) -> Double {
        var out = 0.0
        for segment in segments {
            if time < segment.start { return out }
            if time <= segment.end { return out + (time - segment.start) / segment.rate }
            out += segment.outputLength
        }
        return out
    }

    /// Where each segment starts in the output.
    public var outputStarts: [Double] {
        var out = 0.0
        return segments.map { segment in
            defer { out += segment.outputLength }
            return out
        }
    }
}

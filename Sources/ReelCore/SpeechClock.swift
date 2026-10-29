/// When narration plays during a recording, in seconds from the first frame. Lines never overlap: a `Say` starts when
/// it is reached or when the line before it ends, whichever is later.
public struct SpeechClock: Equatable, Sendable {
    /// When the last line started ends.
    public private(set) var speechEnd = 0.0
    public private(set) var markers: [String: Double] = [:]

    public init() {}

    /// Starts `line` at `now` or after the line before it. Returns when it starts, and when the tape carries on:
    /// at its start for `over`, else at its end.
    public mutating func say(_ line: Narration.Line, now: Double, over: Bool) -> (start: Double, resume: Double) {
        let start = max(now, speechEnd)
        speechEnd = start + line.duration
        for (name, offset) in line.markerOffsets {
            markers[name] = start + offset
        }
        return (start, over ? start : speechEnd)
    }

    /// When the narration reaches `marker`, or nil before its `Say` has started.
    public func time(of marker: String) -> Double? {
        markers[marker]
    }
}

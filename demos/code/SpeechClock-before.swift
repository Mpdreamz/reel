/// When narration plays during a recording, in seconds from the first frame.
/// Lines never overlap: a `Say` starts when it is reached or when the line
/// before it ends, whichever is later.
public struct SpeechClock: Equatable, Sendable {
    /// When the last line started ends.
    public private(set) var speechEnd = 0.0

    /// Starts `line` at `now` or after the line before it. Returns when it
    /// starts, and when the reel carries on: at its start for `over`.
    public mutating func say(
        _ line: Narration.Line, at now: Double, over: Bool
    ) -> (start: Double, resume: Double) {
        let start = max(now, speechEnd)
        speechEnd = start + line.duration
        return (start, over ? start : speechEnd)
    }
}

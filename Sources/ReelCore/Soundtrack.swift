import Foundation

/// The narration of a take, placed where the take recorded each line, and how it mixes with the app's sound.
public struct Soundtrack: Equatable, Sendable {
    public struct Clip: Equatable, Sendable {
        /// The voiced pieces of the line in order (nil for an empty piece), and their lengths.
        public var pieces: [URL?]
        public var lengths: [Double]
        /// Seconds from the first frame.
        public var start: Double
        /// The words, for a subtitle.
        public var text: String

        public var end: Double {
            start + lengths.reduce(0, +)
        }
    }

    public var clips: [Clip]
    public var appVolume: Double
    public var voiceVolume: Double
    /// The app's sound under narration, as a fraction of `appVolume`.
    public var ducking: Double

    /// How long the app's sound takes to dip under a line and come back after it.
    static let ramp = 0.2

    public static let none = Soundtrack(clips: [], appVolume: 1, voiceVolume: 1, ducking: 1)

    /// The narration of `take`, from the voiced lines of `tape`. A line voiced differently from the take (its text,
    /// voice or seed changed) needs a new take: the take was timed to how the line sounded then.
    public static func make(tape: Tape, take: Take, narration: Narration) throws -> Soundtrack {
        var clips: [Clip] = []
        for (step, event) in zip(tape.actions, take.events) {
            guard case let .say(speech, _) = step.command else { continue }
            guard let line = narration.lines[step.line], event.clip == line.key else {
                throw ReelError("line \(step.line) is voiced differently from the take; record it again")
            }
            clips.append(Clip(
                pieces: line.pieces, lengths: line.lengths, start: Double(event.startMs) / 1000, text: speech.text
            ))
        }
        return Soundtrack(
            clips: clips, appVolume: tape.voice.appVolume, voiceVolume: tape.voice.voiceVolume,
            ducking: tape.voice.ducking
        )
    }

    /// The stretches the app's sound is ducked for: each line, with lines closer than two ramps joined so the sound
    /// does not bob up between them.
    public var ducked: [ClosedRange<Double>] {
        var joined: [ClosedRange<Double>] = []
        for clip in clips.sorted(by: { $0.start < $1.start }) where clip.end > clip.start {
            if let last = joined.last, clip.start - last.upperBound < 2 * Self.ramp {
                joined[joined.count - 1] = last.lowerBound ... max(last.upperBound, clip.end)
            } else {
                joined.append(clip.start ... clip.end)
            }
        }
        return joined
    }

    /// The app's volume over time: ramps down to `appVolume × ducking` ending as each ducked stretch starts, and back
    /// up starting as it ends.
    public var appRamps: [(from: Double, to: Double, start: Double, end: Double)] {
        let full = appVolume, low = appVolume * ducking
        return ducked.flatMap { range in
            [
                (full, low, max(0, range.lowerBound - Self.ramp), range.lowerBound),
                (low, full, range.upperBound, range.upperBound + Self.ramp),
            ]
        }
    }

    /// The clips where they land in the output. Narration is never sped up or left out, so each moves as a whole.
    public func mapped(through edit: Edit) -> Soundtrack {
        var moved = self
        moved.clips = clips.map { clip in
            var clip = clip
            clip.start = edit.map(clip.start)
            return clip
        }
        return moved
    }

    public static func == (a: Soundtrack, b: Soundtrack) -> Bool {
        a.clips == b.clips && a.appVolume == b.appVolume && a.voiceVolume == b.voiceVolume && a.ducking == b.ducking
    }
}

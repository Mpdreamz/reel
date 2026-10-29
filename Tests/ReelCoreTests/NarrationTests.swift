import AVFoundation
import Foundation
@testable import ReelCore
import Testing

/// Speaks every word as 0.25 s of a tone, so lengths are known exactly; counts what it voices.
final class FakeVoice: Synthesizer, @unchecked Sendable {
    let hertz: Double
    private(set) var spoken: [String] = []

    init(hertz: Double = 880) {
        self.hertz = hertz
    }

    var fingerprint: String {
        "fake \(hertz)"
    }

    var fileExtension: String {
        "caf"
    }

    func speak(_ text: String, to url: URL) async throws {
        spoken.append(text)
        try writeTone(hertz: hertz, seconds: 0.25 * Double(text.split(separator: " ").count), to: url)
    }
}

/// A mono 48 kHz sine at half amplitude.
func writeTone(hertz: Double, seconds: Double, to url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let frames = AVAudioFrameCount(seconds * 48000)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for i in 0 ..< Int(frames) {
        buffer.floatChannelData![0][i] = Float(0.5 * sin(2 * .pi * hertz * Double(i) / 48000))
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

private func tape(_ body: String) throws -> Tape {
    try Tape.parse("Launch x\nOutput a.mp4\n" + body, relativeTo: URL(fileURLWithPath: "/tmp"))
}

struct NarrationTests {
    @Test func linesAreVoicedInPiecesWithExactMarkerTimes() async throws {
        let dir = try TakeWriterTests().temporaryDirectory()
        let voice = FakeVoice()
        let narration = try await Narration.prepare(
            tape("Say@over \"Pick a track, [pick] then press [play] space to play it.\""),
            into: dir, with: voice, log: { _ in }
        )
        let line = try #require(narration.lines[3])
        #expect(voice.spoken == ["Pick a track,", "then press", "space to play it."])
        #expect(line.lengths.map { ($0 * 100).rounded() / 100 } == [0.75, 0.5, 1])
        #expect(line.markerOffsets.mapValues { ($0 * 100).rounded() / 100 } == ["pick": 0.75, "play": 1.25])
        #expect(abs(line.duration - 2.25) < 0.01)
    }

    @Test func aMarkerAtTheStartIsAnEmptyPiece() async throws {
        let dir = try TakeWriterTests().temporaryDirectory()
        let narration = try await Narration.prepare(
            tape("Say@over \"[now] Click it\""), into: dir, with: FakeVoice(), log: { _ in }
        )
        let line = try #require(narration.lines[3])
        #expect(line.pieces.first == .some(nil))
        #expect(line.markerOffsets == ["now": 0])
    }

    @Test func cachedLinesAreNotVoicedAgain() async throws {
        let dir = try TakeWriterTests().temporaryDirectory()
        let script = try tape("Say \"Hello there\"\nSay \"Goodbye\"")
        let first = FakeVoice()
        let one = try await Narration.prepare(script, into: dir, with: first, log: { _ in })
        let second = FakeVoice()
        var lines: [String] = []
        let two = try await Narration.prepare(script, into: dir, with: second, log: { lines.append($0) })
        #expect(first.spoken.count == 2)
        #expect(second.spoken.isEmpty)
        #expect(one.lines == two.lines)
        #expect(lines == ["narration: 2 lines, all cached"])
        // Another voice is another key.
        let other = try await Narration.prepare(script, into: dir, with: FakeVoice(hertz: 300), log: { _ in })
        #expect(other.lines[3]?.key != one.lines[3]?.key)
    }

    @Test func renderNeverVoicesALine() async throws {
        let dir = try TakeWriterTests().temporaryDirectory()
        await #expect(throws: ReelError.self) {
            try await Narration
                .prepare(tape("Say \"New words\""), into: dir, with: FakeVoice(), voicing: false) { _ in }
        }
    }
}

struct SpeechClockTests {
    private func line(_ seconds: Double, markers: [String: Double] = [:]) -> Narration.Line {
        // Pieces split at the markers, in order.
        let cuts = markers.sorted { $0.value < $1.value }
        var lengths: [Double] = [], last = 0.0
        for (_, at) in cuts {
            lengths.append(at - last)
            last = at
        }
        lengths.append(seconds - last)
        return Narration.Line(
            pieces: lengths.map { _ in nil }, lengths: lengths, markers: cuts.map(\.key), key: "k"
        )
    }

    @Test func aBlockingLineResumesWhenItEnds() {
        var clock = SpeechClock()
        let (start, resume) = clock.say(line(2), now: 1, over: false)
        #expect(start == 1)
        #expect(resume == 3)
    }

    @Test func anOverLineResumesAtOnceAndPlacesItsMarkers() {
        var clock = SpeechClock()
        let (start, resume) = clock.say(line(3, markers: ["a": 1, "b": 2.5]), now: 1, over: true)
        #expect(start == 1)
        #expect(resume == 1)
        #expect(clock.time(of: "a") == 2)
        #expect(clock.time(of: "b") == 3.5)
        #expect(clock.time(of: "c") == nil)
        #expect(clock.speechEnd == 4)
    }

    @Test func linesNeverOverlap() {
        var clock = SpeechClock()
        _ = clock.say(line(3), now: 0, over: true)
        let (start, resume) = clock.say(line(1), now: 1, over: true)
        #expect(start == 3)
        #expect(resume == 3)
        let later = clock.say(line(1), now: 10, over: false)
        #expect(later.start == 10)
        #expect(later.resume == 11)
    }
}

struct SoundtrackTests {
    private func soundtrack(_ spans: [(Double, Double)], ducking: Double = 0.25) -> Soundtrack {
        Soundtrack(
            clips: spans.map { Soundtrack.Clip(pieces: [nil], lengths: [$0.1 - $0.0], start: $0.0, text: "") },
            appVolume: 0.8, voiceVolume: 1, ducking: ducking
        )
    }

    @Test func linesCloseTogetherDuckAsOne() {
        let track = soundtrack([(1, 2), (2.3, 3), (5, 6)])
        #expect(track.ducked == [1 ... 3, 5 ... 6])
    }

    @Test func rampsDipBeforeALineAndRiseAfterIt() {
        let ramps = soundtrack([(1, 2)]).appRamps
        #expect(ramps.count == 2)
        #expect(ramps[0] == (0.8, 0.2, 0.8, 1))
        #expect(ramps[1] == (0.2, 0.8, 2, 2.2))
        // A line at the very start ramps from zero.
        #expect(soundtrack([(0.1, 1)]).appRamps[0].start == 0)
    }

    @Test func aLineVoicedDifferentlyNeedsANewTake() throws {
        let script = try Tape.parse("Launch x\nOutput a.mp4\nSay \"Hi\"", relativeTo: URL(fileURLWithPath: "/tmp"))
        let take = Take(
            width: 10, height: 10, scale: 1, frameRate: 30, audio: true, durationMs: 1000,
            events: [Take.Event(line: 3, command: "Say \"Hi\"", startMs: 0, endMs: 250, clip: "old")]
        )
        let narration = Narration(lines: [3: Narration.Line(pieces: [nil], lengths: [0.25], markers: [], key: "new")])
        #expect(throws: ReelError.self) { try Soundtrack.make(tape: script, take: take, narration: narration) }
    }

    @Test func subtitlesTakeTheCaptionsPlace() {
        let overlays = OverlayPlan.adding(
            subtitles: [Soundtrack.Clip(pieces: [nil], lengths: [1], start: 2, text: "Hello there")],
            to: [
                Overlay(kind: .caption("Long caption"), start: 1, end: 5),
                Overlay(kind: .keys("⌘S"), start: 2, end: 3),
            ]
        )
        #expect(overlays == [
            Overlay(kind: .caption("Long caption"), start: 1, end: 2),
            Overlay(kind: .keys("⌘S"), start: 2, end: 3),
            Overlay(kind: .caption("Hello there"), start: 2, end: 3),
            Overlay(kind: .caption("Long caption"), start: 3, end: 5),
        ])
    }
}

/// The mix itself: a take whose app sound is a 440 Hz tone, narrated by an 880 Hz "voice" from 1 to 2 s.
struct MixTests {
    @Test func narrationPlaysWhereTheTakeSaysAndTheAppDucksUnderIt() async throws {
        let writer = TakeWriterTests()
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await takeWithSound(to: movie, seconds: 3, hertz: 440, in: dir)
        let clip = dir.appending(path: "voice.caf")
        try writeTone(hertz: 880, seconds: 1, to: clip)
        let soundtrack = Soundtrack(
            clips: [Soundtrack.Clip(pieces: [clip], lengths: [1], start: 1, text: "")],
            appVolume: 1, voiceVolume: 1, ducking: 0.2
        )
        let take = Take(width: 320, height: 200, scale: 1, frameRate: 30, audio: true, durationMs: 3000, events: [])
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Renderer.render(movie, take: take, overlays: [], soundtrack: soundtrack, to: output)

        let samples = try await mono(output.url)
        let before = samples[Int(0.2 * 48000) ..< Int(0.7 * 48000)]
        let during = samples[Int(1.3 * 48000) ..< Int(1.8 * 48000)]
        let after = samples[Int(2.4 * 48000) ..< Int(2.9 * 48000)]
        let app = (before: level(before, 440), during: level(during, 440), after: level(after, 440))
        let voice = (before: level(before, 880), during: level(during, 880), after: level(after, 880))
        #expect(voice.during > 0.1, "the narration plays from 1 s")
        #expect(voice.before < 0.01 && voice.after < 0.01, "and only then")
        #expect(app.before > 0.1 && app.after > 0.1, "the app plays at full volume around it")
        #expect(abs(app.during / app.before - 0.2) < 0.05, "and at 20% under it (\(app.during / app.before))")
    }

    /// A still take with a tone for the app's sound: a silent take from the writer, and the tone added by a passthrough
    /// export (feeding the writer three seconds of picture and sound by hand stalls on its interleaving).
    private func takeWithSound(to url: URL, seconds: Double, hertz: Double, in dir: URL) async throws {
        let silent = dir.appending(path: "silent.mov")
        try await TakeWriterTests().writeTake(to: silent, seconds: seconds, audio: false, shade: 100)
        let tone = dir.appending(path: "app.caf")
        try writeTone(hertz: hertz, seconds: seconds, to: tone)
        let composition = AVMutableComposition()
        // The assets are kept: a track whose asset is gone cannot be inserted.
        let assets = [AVURLAsset(url: silent), AVURLAsset(url: tone)]
        for (asset, type) in zip(assets, [AVMediaType.video, .audio]) {
            let track = try #require(try await asset.loadTracks(withMediaType: type).first)
            let into = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)
            try await into?.insertTimeRange(track.load(.timeRange), of: track, at: .zero)
        }
        let export = try #require(AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ))
        try await export.export(to: url, as: .mov)
        withExtendedLifetime(assets) {}
    }

    /// The amplitude of one frequency (Goertzel).
    private func level(_ samples: ArraySlice<Float>, _ hertz: Double) -> Double {
        let k = 2 * cos(2 * .pi * hertz / 48000)
        var s1 = 0.0, s2 = 0.0
        for x in samples {
            (s1, s2) = (Double(x) + k * s1 - s2, s1)
        }
        let power = s1 * s1 + s2 * s2 - k * s1 * s2
        return 2 * power.squareRoot() / Double(samples.count)
    }

    private func mono(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        reader.startReading()
        var all: [Float] = []
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / 4)
            floats.withUnsafeMutableBytes {
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            all += floats
        }
        return all
    }
}

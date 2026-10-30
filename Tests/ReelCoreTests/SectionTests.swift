import AVFoundation
import CoreMedia
import Foundation
@testable import ReelCore
import Testing

private func tape(_ body: String) throws -> Tape {
    try Tape.parse("Launch x\nOutput a.mp4\n" + body, relativeTo: URL(fileURLWithPath: "/tmp/demos"))
}

struct SectionParsingTests {
    @Test func introAndOutro() throws {
        let parsed = try tape("""
        Intro@slide-left,ease-out,800ms "Musicbox" "A music player for your Mac" 4s
        Outro "Get it"
        Set IntroBackground media/intro.mov
        Set OutroBackground #1d2b3a
        """)
        let intro = try #require(parsed.intro)
        #expect(intro.title == "Musicbox")
        #expect(intro.subtitle == "A music player for your Mac")
        #expect(intro.duration == .seconds(4))
        #expect(intro.background == .video(URL(fileURLWithPath: "/tmp/demos/media/intro.mov")))
        #expect(intro.transition == SectionTransition(kind: .slideLeft, easing: .easeOut, duration: .milliseconds(800)))
        let outro = try #require(parsed.outro)
        #expect(outro.subtitle == nil && outro.duration == nil)
        #expect(outro.transition == .standard)
        guard case let .color(r, g, b) = outro.background else { Issue.record("expected a colour"); return }
        #expect(abs(r - 29 / 255) < 1e-9 && abs(g - 43 / 255) < 1e-9 && abs(b - 58 / 255) < 1e-9)
        #expect(try tape("Intro \"A\"").intro?.background == .standard)
        // No title: the background video alone, for a designed sting.
        let sting = try #require(try tape("Outro@fade 2s\nSet OutroBackground //sting.mov".replacingOccurrences(
            of: "//", with: "/tmp/"
        )).outro)
        #expect(sting.title.isEmpty && sting.subtitle == nil && sting.duration == .seconds(2))
        #expect(try tape("Intro@cut,1s \"A\"").intro?.transition.duration == .zero, "a cut takes no time")
        #expect(try tape("Set IntroBackground a.png\nIntro \"A\"").intro?.background
            == .image(URL(fileURLWithPath: "/tmp/demos/a.png")))
    }

    @Test(arguments: [
        (
            "Intro",
            "an Intro without a title shows its background on its own, so that must be a video: Set IntroBackground <video>"
        ),
        ("Intro Musicbox", "expected Intro [\"<title>\" [\"<subtitle>\"]] [duration]"),
        ("Intro 2s 3s", "expected Intro [\"<title>\" [\"<subtitle>\"]] [duration]"),
        ("Intro \"A\" 2s \"B\"", "expected Intro [\"<title>\" [\"<subtitle>\"]] [duration]"),
        ("Outro \"A\"\nOutro \"B\"", "a reel has one Outro"),
        (
            "Intro@spin \"A\"",
            "'@spin' is not a transition; write a kind (crossfade, fade, slide-left, slide-right, slide-up, slide-down, zoom, wipe-left, wipe-right, wipe-up, wipe-down, cut), an easing and a duration, such as @slide-left,ease-out,800ms"
        ),
        ("Set IntroBackground #12345", "'#12345' is not a colour; write #rrggbb, such as #1d2b3a"),
        (
            "Set IntroBackground intro.txt",
            "a background is #rrggbb, an image (.png, .jpg, .heic) or a video (.mov, .mp4), not 'intro.txt'"
        ),
    ])
    func errors(body: String, message: String) {
        let line = 2 + body.split(separator: "\n").count
        #expect(throws: TapeError(line: line, message: message)) { try tape(body) }
    }
}

struct ArrangementTests {
    private let crossfade = SectionTransition(kind: .crossfade, easing: .linear, duration: .milliseconds(500))

    @Test func overlappingTransitionsShortenTheMovie() throws {
        let arrangement = try Arrangement(
            intro: 2, introTransition: crossfade, main: 10, outro: 3,
            outroTransition: SectionTransition(kind: .slideLeft, easing: .linear, duration: .seconds(1))
        )
        #expect(arrangement.main == (1.5, 10))
        #expect(arrangement.into?.start == 1.5 && arrangement.into?.end == 2)
        #expect(arrangement.outro?.start == 10.5)
        #expect(arrangement.outOf?.start == 10.5 && arrangement.outOf?.end == 11.5)
        #expect(arrangement.duration == 13.5)
    }

    @Test func aFadeGoesThroughBlackAcrossTheCut() throws {
        let fade = SectionTransition(kind: .fade, easing: .linear, duration: .seconds(1))
        let arrangement = try Arrangement(intro: 2, introTransition: fade, main: 4, outro: nil, outroTransition: nil)
        #expect(arrangement.main.start == 2)
        #expect(arrangement.into?.start == 1.5 && arrangement.into?.end == 2.5)
        #expect(arrangement.look(.intro, at: 1.75).opacity == 0.5)
        #expect(arrangement.look(.intro, at: 2).opacity == 0, "black at the cut")
        #expect(arrangement.look(.main, at: 2).opacity == 0)
        #expect(arrangement.look(.main, at: 2.25).opacity == 0.5)
        #expect(arrangement.duration == 6)
    }

    @Test func crossfadesFadeOnlyTheSectionOnTop() throws {
        let arrangement = try Arrangement(
            intro: 2, introTransition: crossfade, main: 4, outro: 2, outroTransition: crossfade
        )
        #expect(arrangement.look(.intro, at: 1.75).opacity == 0.5)
        #expect(arrangement.look(.main, at: 1.75).opacity == 1, "the demo beneath shows as the intro goes")
        #expect(arrangement.look(.outro, at: 5.25).opacity == 0.5)
        #expect(arrangement.look(.main, at: 5.25).opacity == 1)
        #expect(arrangement.volume(.intro, at: 1.75) == 0.5 && arrangement.volume(.main, at: 1.75) == 0.5)
        #expect(arrangement.look(.main, at: 3) == .still)
    }

    @Test func aSectionShorterThanItsTransitionIsRefused() {
        #expect(throws: ReelError.self) {
            try Arrangement(intro: 0.3, introTransition: crossfade, main: 4, outro: nil, outroTransition: nil)
        }
    }

    @Test func slidesPushTheOneBeforeOut() {
        let out = Look.of(.slideLeft, progress: 0.25, outgoing: true, onTop: true)
        let coming = Look.of(.slideLeft, progress: 0.25, outgoing: false, onTop: false)
        #expect(out.offset == CGPoint(x: -0.25, y: 0))
        #expect(coming.offset == CGPoint(x: 0.75, y: 0), "comes in from the right")
        #expect(Look.of(.slideUp, progress: 0.5, outgoing: false, onTop: false).offset == CGPoint(x: 0, y: 0.5))
        #expect(Look.of(.slideDown, progress: 1, outgoing: true, onTop: true).offset == CGPoint(x: 0, y: 1))
    }

    @Test(arguments: [
        (
            TransitionKind.wipeLeft,
            CGRect(x: 0, y: 0, width: 0.75, height: 1),
            CGRect(x: 0.75, y: 0, width: 0.25, height: 1)
        ),
        (.wipeRight, CGRect(x: 0.25, y: 0, width: 0.75, height: 1), CGRect(x: 0, y: 0, width: 0.25, height: 1)),
        (.wipeUp, CGRect(x: 0, y: 0, width: 1, height: 0.75), CGRect(x: 0, y: 0.75, width: 1, height: 0.25)),
        (.wipeDown, CGRect(x: 0, y: 0.25, width: 1, height: 0.75), CGRect(x: 0, y: 0, width: 1, height: 0.25)),
    ])
    func wipesInEveryDirection(kind: TransitionKind, going: CGRect, coming: CGRect) {
        // A quarter through: three quarters of the one going out still shows, a quarter of the one coming in.
        #expect(Look.of(kind, progress: 0.25, outgoing: true, onTop: true).crop == going)
        #expect(Look.of(kind, progress: 0.25, outgoing: false, onTop: true).crop == coming)
    }

    @Test func wipesAndZoomsWorkOnTheSectionOnTop() {
        #expect(Look.of(.wipeLeft, progress: 0.25, outgoing: true, onTop: true).crop
            == CGRect(x: 0, y: 0, width: 0.75, height: 1))
        #expect(Look.of(.wipeLeft, progress: 0.25, outgoing: false, onTop: true).crop
            == CGRect(x: 0.75, y: 0, width: 0.25, height: 1))
        #expect(Look.of(.wipeUp, progress: 0.25, outgoing: false, onTop: false) == .still)
        let zoom = Look.of(.zoom, progress: 0.5, outgoing: true, onTop: true)
        #expect(zoom.opacity == 0.5 && zoom.scale == 1.15)
        #expect(Look.of(.cut, progress: 1, outgoing: true, onTop: true).opacity == 0)
    }
}

/// Real assemblies of generated clips.
struct AssemblyTests {
    let writer = TakeWriterTests()

    @Test func anIntroAndAnOutroAroundTheDemo() async throws {
        let dir = try writer.temporaryDirectory()
        let demo = dir.appending(path: "demo.mov")
        try await writer.writeTake(to: demo, seconds: 2, audio: false, shade: 128)
        let intro = Section(
            title: "Musicbox", subtitle: "A music player", duration: .seconds(1), background: .color(1, 0, 0),
            transition: SectionTransition(kind: .crossfade, easing: .linear, duration: .milliseconds(400))
        )
        let outro = Section(
            title: "Get it", subtitle: nil, duration: .seconds(1), background: .color(0, 0, 1),
            transition: SectionTransition(kind: .slideLeft, easing: .linear, duration: .milliseconds(400))
        )
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Assembler.assemble(main: demo, intro: intro, outro: outro, frameRate: 30, in: dir, to: output)

        let movie = AVURLAsset(url: output.url)
        // 1 + 2 - 0.4 + 1 - 0.4 seconds.
        #expect(try await abs(movie.load(.duration).seconds - 3.2) < 0.06)
        // Corners are background; the middle of the intro has its title's white.
        let intro0 = try await Frame(movie, at: 0.5)
        #expect(intro0.colour(10, 10) == "red")
        #expect(intro0.brightest(row: 85, from: 100, to: 220) > 220, "the title is drawn")
        #expect(try await Frame(movie, at: 1.5).colour(10, 10) == "grey")
        // Halfway through the slide (2.2 to 2.6 s) the demo has gone half out to the left, the outro half in.
        let sliding = try await Frame(movie, at: 2.4)
        #expect(sliding.colour(60, 150) == "grey")
        #expect(sliding.colour(260, 150) == "blue")
        #expect(try await Frame(movie, at: 3.1).colour(10, 190) == "blue")
    }

    @Test func anOutroWithoutATitleIsItsVideoAlone() async throws {
        let dir = try writer.temporaryDirectory()
        let demo = dir.appending(path: "demo.mov")
        try await writer.writeTake(to: demo, seconds: 1, audio: false, shade: 128)
        let sting = dir.appending(path: "sting.mov")
        try await writer.writeTake(to: sting, seconds: 1, audio: false, shade: 40)
        let outro = Section(
            title: "", subtitle: nil, duration: nil, background: .video(sting),
            transition: SectionTransition(kind: .cut, easing: .linear, duration: .zero)
        )
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Assembler.assemble(main: demo, intro: nil, outro: outro, frameRate: 30, in: dir, to: output)
        let movie = AVURLAsset(url: output.url)
        // Nothing white over the sting's dark grey where a title would be.
        #expect(try await Frame(movie, at: 1.5).brightest(row: 85, from: 100, to: 220) < 80)
    }

    @Test func aVideoBackgroundKeepsItsSound() async throws {
        let dir = try writer.temporaryDirectory()
        let demo = dir.appending(path: "demo.mov")
        try await writer.writeTake(to: demo, seconds: 1, audio: false, shade: 128)
        // The intro's video: a still take with a 440 Hz tone added.
        let silent = dir.appending(path: "silent.mov")
        try await writer.writeTake(to: silent, seconds: 1.5, audio: false, shade: 40)
        let tone = dir.appending(path: "tone.caf")
        try writeTone(hertz: 440, seconds: 1.5, to: tone)
        let background = dir.appending(path: "background.mov")
        let composition = AVMutableComposition()
        let sources = [AVURLAsset(url: silent), AVURLAsset(url: tone)]
        for (asset, type) in zip(sources, [AVMediaType.video, .audio]) {
            let track = try #require(try await asset.loadTracks(withMediaType: type).first)
            try await composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)?
                .insertTimeRange(track.load(.timeRange), of: track, at: .zero)
        }
        let export = try #require(AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ))
        try await export.export(to: background, as: .mov)

        let intro = Section(
            title: "Hello", subtitle: nil, duration: nil, background: .video(background),
            transition: SectionTransition(kind: .cut, easing: .linear, duration: .zero)
        )
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Assembler.assemble(main: demo, intro: intro, outro: nil, frameRate: 30, in: dir, to: output)
        let movie = AVURLAsset(url: output.url)
        #expect(try await abs(movie.load(.duration).seconds - 2.5) < 0.06, "the video's own 1.5 s, then the demo")
        let sound = try await mono(movie)
        // The demo has no sound of its own, so the sound may end with the intro: silence either way.
        func window(_ from: Double, _ to: Double) -> ArraySlice<Float> {
            sound[min(sound.count, Int(from * 48000)) ..< min(sound.count, Int(to * 48000))]
        }
        let during = window(0.3, 1.2)
        let after = window(1.7, 2.4)
        #expect(rms(during) > 0.1, "the background's tone plays under the intro")
        #expect(rms(after) < 0.01, "and stops with it")
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        (samples.map { Double($0 * $0) }.reduce(0, +) / Double(max(1, samples.count))).squareRoot()
    }

    private func mono(_ asset: AVAsset) async throws -> [Float] {
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

/// One frame of a movie, read as RGB.
private struct Frame {
    let width: Int
    let bytes: [UInt8]

    init(_ asset: AVAsset, at time: Double) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        self.bytes = bytes
    }

    func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    func colour(_ x: Int, _ y: Int) -> String {
        switch pixel(x, y) {
        case let (r, g, b) where r > 150 && g < 90 && b < 90: "red"
        case let (r, g, b) where b > 150 && r < 90 && g < 90: "blue"
        case let (r, g, b) where abs(r - g) < 20 && abs(g - b) < 20 && r > 90 && r < 180: "grey"
        case let pixel: "\(pixel)"
        }
    }

    func brightest(row: Int, from: Int, to: Int) -> Int {
        (from ..< to).map { x in
            let p = pixel(x, row)
            return min(p.0, p.1, p.2)
        }.max() ?? 0
    }
}

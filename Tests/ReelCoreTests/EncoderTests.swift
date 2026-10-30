import AVFoundation
import ImageIO
@testable import ReelCore
import Testing

/// Movie Outputs compressed from generated takes, read back with AVFoundation.
struct EncoderTests {
    let writer = TakeWriterTests()

    @Test func byDefaultH264AtTheMoviesOwnSizeWithItsSound() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 1, audio: true)
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        let result = try await Encoder.encode(movie, to: output, with: .standard, frameRate: 30)
        #expect(result.size == CGSize(width: 320, height: 200))
        let read = try await Movie(output.url)
        #expect(read.codec == kCMVideoCodecType_H264)
        #expect(read.size == CGSize(width: 320, height: 200))
        #expect(abs(read.duration - 1) < 0.05)
        #expect(read.soundCodec == kAudioFormatMPEG4AAC)
        // The tone survives: a 0.5 amplitude sine has an RMS of about 0.35.
        #expect(try await writer.rms(of: AVURLAsset(url: output.url)) > 0.3)
        #expect(result.bytes > 0)
        #expect(result.bytes == fileSize(output.url))
    }

    @Test func hevcWhenAsked() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 0.5, audio: false)
        let output = Output(url: dir.appending(path: "out.mov"), format: .mov)
        try await Encoder.encode(
            movie, to: output, with: Encoding(quality: 65, codec: .hevc, width: nil), frameRate: 30
        )
        let read = try await Movie(output.url)
        #expect(read.codec == kCMVideoCodecType_HEVC)
        #expect(read.soundCodec == nil)
    }

    @Test func scaledDownToTheWidthAskedAndNeverUp() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 0.5, audio: false)
        for (width, expected) in [(160, CGSize(width: 160, height: 100)), (1000, CGSize(width: 320, height: 200))] {
            let output = Output(url: dir.appending(path: "out-\(width).mp4"), format: .mp4)
            let result = try await Encoder.encode(
                movie, to: output, with: Encoding(quality: 65, codec: .h264, width: width), frameRate: 30
            )
            #expect(result.size == expected)
            #expect(try await Movie(output.url).size == expected)
        }
    }

    @Test func aQualityStandsInAsBitsPerPixelWhereTheEncoderTakesNone() {
        // Quality 65 on the Musicbox take came to about 0.9 Mbit/s at 1920x1256 and 30 fps.
        let rate = 1920 * 1256 * 30 * Encoder.bitsPerPixel(quality: 65)
        #expect((0.8e6 ... 1.0e6).contains(rate))
        #expect(Encoder.bitsPerPixel(quality: 100) > Encoder.bitsPerPixel(quality: 30))
    }

    @Test func sizesAreEvenAndInProportion() {
        let natural = CGSize(width: 3124, height: 2044)
        #expect(Encoding.standard.size(for: natural) == natural)
        #expect(Encoding(quality: 65, codec: .h264, width: 1920).size(for: natural) == CGSize(
            width: 1920,
            height: 1256
        ))
        #expect(Encoding(quality: 65, codec: .h264, width: 161).size(for: CGSize(width: 320, height: 200))
            == CGSize(width: 160, height: 100))
    }

    @Test func aTapesSettingsReachItsMoviesAndItsGifsShareTheLosslessMovie() async throws {
        let dir = try writer.temporaryDirectory()
        let location = TakeLocation(tape: dir.appending(path: "demo.reel"))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try await writer.writeTake(to: location.movie, seconds: 1, audio: false)
        try location.write(Take(
            width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 1000,
            events: [Take.Event(line: 7, command: "Sleep 1s", startMs: 0, endMs: 1000)]
        ))
        let tape = try Tape.parse(
            "Launch x\nOutput demo.mp4\nOutput demo.gif\nSet Codec hevc\nSet VideoWidth 160\nSet Quality 40\nSleep 1s",
            relativeTo: dir
        )
        var lines: [String] = []
        try await Renderer.render(tape: tape, from: location, log: { lines.append($0) })
        let read = try await Movie(dir.appending(path: "demo.mp4"))
        #expect(read.codec == kCMVideoCodecType_HEVC)
        #expect(read.size == CGSize(width: 160, height: 100))
        #expect(lines.first?.hasSuffix("demo.mp4 (0.0 MB, HEVC 160x100, quality 40)") == true)
        #expect(lines.count == 2)
        // The GIF comes from the lossless movie, not the compressed one: it is as wide as the take.
        let gif = try #require(CGImageSourceCreateWithURL(dir.appending(path: "demo.gif") as CFURL, nil))
        #expect(try #require(CGImageSourceCreateImageAtIndex(gif, 0, nil)).width == 320)
        // And nothing lossless is left behind.
        let left = try FileManager.default.contentsOfDirectory(atPath: location.directory.path)
        #expect(!left.contains { $0.hasPrefix("lossless-") })
    }

    @Test func lowerQualityIsASmallerFile() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 0.5, audio: false, noise: true)
        var sizes: [Int] = []
        for quality in [20, 65, 95] {
            let output = Output(url: dir.appending(path: "q\(quality).mp4"), format: .mp4)
            try await sizes.append(Encoder.encode(
                movie, to: output, with: Encoding(quality: quality, codec: .h264, width: nil), frameRate: 30
            ).bytes)
        }
        #expect(sizes[0] < sizes[1])
        #expect(sizes[1] < sizes[2])
    }
}

/// What a written movie holds.
private struct Movie {
    var codec: FourCharCode?
    var soundCodec: AudioFormatID?
    var size: CGSize
    var duration: Double

    init(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let picture = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let formats = try await picture.load(.formatDescriptions)
        codec = formats.first.map(CMFormatDescriptionGetMediaSubType)
        size = try await picture.load(.naturalSize)
        duration = try await asset.load(.duration).seconds
        if let sound = try await asset.loadTracks(withMediaType: .audio).first {
            let formats = try await sound.load(.formatDescriptions)
            soundCodec = formats.first
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mFormatID }
        }
    }
}

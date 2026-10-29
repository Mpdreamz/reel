import AVFoundation
import CoreImage
import Foundation
@testable import ReelCore
import Testing

private func tape(_ body: String) throws -> Tape {
    try Tape.parse("Launch x\nOutput a.mp4\n" + body, relativeTo: URL(fileURLWithPath: "/tmp/demos"))
}

struct FramingParsingTests {
    @Test func shapesBackgroundAndPadding() throws {
        let parsed = try Tape.parse("""
        Launch x
        Output a.mp4
        Output@16:9 wide.mp4
        Output@1:1 square.gif
        Output@9:16 story.mp4
        Output@1080x1080 small.mp4
        Set Background media/bg.png
        Set Padding 8%
        """, relativeTo: URL(fileURLWithPath: "/tmp/demos"))
        #expect(parsed.outputs.map(\.shape) == [nil, .aspect(16, 9), .aspect(1, 1), .aspect(9, 16), .size(1080, 1080)])
        #expect(parsed.background == .image(URL(fileURLWithPath: "/tmp/demos/media/bg.png")))
        #expect(parsed.padding == 0.08)
        let plain = try tape("")
        #expect(plain.background == nil && plain.padding == Framing.defaultPadding)
    }

    @Test(arguments: [
        (
            "Output@wide a.mov",
            "'@wide' is not a shape; write an aspect such as @16:9, @1:1 or @9:16, or a size such as @1080x1080"
        ),
        (
            "Output@16:0 a.mov",
            "'@16:0' is not a shape; write an aspect such as @16:9, @1:1 or @9:16, or a size such as @1080x1080"
        ),
        (
            "Output@10x10 a.mov",
            "'@10x10' is not a shape; write an aspect such as @16:9, @1:1 or @9:16, or a size such as @1080x1080"
        ),
        ("Set Padding 50%", "Padding must be a percentage from 0% to 30%, not '50%'"),
        (
            "Set Background plaid",
            "a background is #rrggbb, an image (.png, .jpg, .heic) or a video (.mov, .mp4), not 'plaid'"
        ),
    ])
    func errors(line: String, message: String) {
        #expect(throws: TapeError(line: 3, message: message)) { try tape(line) }
    }
}

struct FramingGeometryTests {
    let recording = CGSize(width: 2560, height: 1600)

    private func frame(_ shape: Output.Shape?, padding: Double = 0.06) -> Framing {
        Framing.make(recording: recording, scale: 2, shape: shape, padding: padding, background: .standard)
    }

    /// The content keeps the recording's shape, sits centred, and keeps at least the padding from every edge.
    private func check(_ framing: Framing, padding: Double = 0.06) {
        let c = framing.content, canvas = framing.canvas
        #expect(abs(c.width / c.height - recording.width / recording.height) < 0.01, "the recording's shape")
        #expect(abs(c.midX - canvas.width / 2) <= 1 && abs(c.midY - canvas.height / 2) <= 1, "centred")
        let pad = padding * min(canvas.width, canvas.height)
        #expect(c.minX >= pad - 1 && c.minY >= pad - 1, "room around it (\(c), \(canvas))")
        #expect(Int(canvas.width) % 2 == 0 && Int(canvas.height) % 2 == 0, "even sizes, as H.264 wants")
    }

    @Test func itsOwnShapeAddsThePadding() {
        let framing = frame(nil)
        check(framing)
        #expect(framing.content.size == recording, "at its own size")
        #expect(framing.canvas.width > recording.width && framing.canvas.height > recording.height)
    }

    @Test(arguments: [(1, 1), (16, 9), (4, 3)])
    func aspectsHoldTheRecordingAtItsOwnSize(w: Int, h: Int) {
        let framing = frame(.aspect(w, h))
        check(framing)
        #expect(abs(framing.canvas.width / framing.canvas.height - Double(w) / Double(h)) < 0.01)
        #expect(framing.content.width >= recording.width - 2, "not shrunk (\(framing.content.width))")
    }

    @Test func aTallCanvasIsCappedAt3840() {
        let framing = frame(.aspect(9, 16))
        check(framing)
        #expect(framing.canvas.height == 3840 && abs(framing.canvas.width - 2160) <= 2, "\(framing.canvas)")
    }

    @Test func anExactSizeFitsTheRecordingIn() {
        let framing = frame(.size(1080, 1080))
        check(framing)
        #expect(framing.canvas == CGSize(width: 1080, height: 1080))
        #expect(framing.content.width < recording.width)
        // The corner shrinks with the recording: 12 points at 2×, scaled as the recording is.
        #expect(abs(framing.corner - 24 * framing.content.width / recording.width) < 0.01)
    }

    @Test func morePaddingMeansMoreRoom() {
        #expect(frame(.size(1080, 1080), padding: 0.2).content.width < frame(.size(1080, 1080)).content.width)
    }
}

/// Real framed renders of a plain grey take.
struct FramerRenderTests {
    let writer = TakeWriterTests()

    private func framed(_ background: Background, shape: Output.Shape = .aspect(1, 1), seconds: Double = 1)
        async throws -> (AVURLAsset, Framing)
    {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: seconds, audio: false, shade: 128)
        let framing = Framing.make(
            recording: CGSize(width: 320, height: 200), scale: 2, shape: shape, padding: 0.1, background: background
        )
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Framer.frame(movie, with: framing, frameRate: 30, to: output, lossless: false)
        return (AVURLAsset(url: output.url), framing)
    }

    @Test func theRecordingSitsOnItsBackgroundWithRoundedCornersAndAShadow() async throws {
        let (movie, framing) = try await framed(.color(1, 0, 0))
        let track = try #require(try await movie.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == framing.canvas, "the canvas's size")
        let frame = try await Pixels(movie, at: 0.5)
        let c = framing.content
        #expect(frame.colour(4, 4) == "red", "the background in the corner")
        #expect(frame.colour(Int(c.midX), Int(c.midY)) == "grey", "the recording in the middle")
        // Just inside the content's corner the rounding shows the background; along its edge, the recording.
        #expect(frame.colour(Int(c.minX) + 1, Int(c.minY) + 1) != "grey", "a rounded corner")
        #expect(frame.colour(Int(c.minX) + 2, Int(c.midY)) == "grey", "a straight edge")
        // Below the window the shadow darkens the background; well away from it, none.
        let under = frame.pixel(Int(c.midX), Int(c.maxY) + 3), away = frame.pixel(4, 4)
        #expect(under.0 < away.0 - 25, "a shadow below (\(under) against \(away))")
    }

    @Test func anImageFillsTheBackground() async throws {
        let dir = try writer.temporaryDirectory()
        let png = dir.appending(path: "blue.png")
        let context = CIContext()
        try context.writePNGRepresentation(
            of: CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(
                x: 0,
                y: 0,
                width: 64,
                height: 40
            )),
            to: png, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        let (movie, _) = try await framed(.image(png))
        let frame = try await Pixels(movie, at: 0.5)
        #expect(frame.colour(4, 4) == "blue")
    }

    @Test func aShortVideoBackgroundLoops() async throws {
        let dir = try writer.temporaryDirectory()
        let background = dir.appending(path: "bg.mov")
        // A 0.5 s fade from black to white, under a 1.5 s take: the loop starts over at 0.5 s and 1 s.
        try await writer.writeTake(to: background, seconds: 0.5, audio: false)
        let (movie, _) = try await framed(.video(background), seconds: 1.5)
        #expect(try await abs(movie.load(.duration).seconds - 1.5) < 0.06, "as long as the take, not the background")
        // Bright late in each pass of the loop: a background that played once would be black (nothing) by 1.45 s.
        let early = try await Pixels(movie, at: 0.05).pixel(4, 4).0
        let bright = try await Pixels(movie, at: 0.45).pixel(4, 4).0
        let again = try await Pixels(movie, at: 1.45).pixel(4, 4).0
        #expect(bright > early + 100, "it moves within the loop (\(early) → \(bright))")
        #expect(abs(again - bright) < 30, "the same moment of the next pass at 1.45 s (\(bright), \(again))")
    }
}

/// One frame of a movie, read as RGB.
private struct Pixels {
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
}

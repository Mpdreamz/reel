import AVFoundation
import CoreMedia
@testable import ReelCore
import Testing

/// Renders a plain grey take with a caption, a key badge and a ripple, and reads pixels where each is drawn, when
/// it should and should not show.
struct RenderTests {
    // The generated take's size; at 2× its window is 160×100 points.
    let width = TakeWriterTests().width, height = TakeWriterTests().height

    @Test func overlaysShowWhereAndWhenThePlanSays() async throws {
        let writer = TakeWriterTests()
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 2, audio: false, shade: 128)
        let overlays = [
            Overlay(kind: .caption("Hello"), start: 0, end: 0.8),
            Overlay(kind: .keys("⌘S"), start: 0.2, end: 1.4),
            Overlay(kind: .ripple(CGPoint(x: 50, y: 50)), start: 1.1, end: 1.6),
        ]
        let take = Take(width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 2000, events: [])
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Renderer.render(movie, take: take, overlays: overlays, to: output)

        let video = AVURLAsset(url: output.url)
        // Just inside the bottom of each pill (its padding, so the dark background rather than text), and the
        // ripple's centre: 50 points at 2× from the top left.
        let caption = (x: width / 2, y: height - Int(Double(height) * 0.06) - 3)
        let badge = (x: width / 2, y: height - Int(Double(height) * 0.2) - 3)
        let ripple = (x: 100, y: 100)

        // The grey as rendered (export converts its colour slightly), from a frame nothing is drawn on.
        let plain = try await pixels(video, at: 1.9, [caption])[0]
        let isPlain = { (value: Int) in abs(value - plain) < 8 }

        let early = try await pixels(video, at: 0.5, [caption, badge, ripple])
        #expect(early[0] < plain - 60, "caption shows at 0.5 s")
        #expect(early[1] < plain - 60, "key badge shows at 0.5 s")
        // Their text: white strokes somewhere across the middle of each pill.
        let captionText = try await brightest(video, at: 0.5, row: caption.y - 12, from: width / 3, to: width * 2 / 3)
        let badgeText = try await brightest(video, at: 0.5, row: badge.y - 14, from: width / 3, to: width * 2 / 3)
        #expect(captionText > 200, "the caption's text is drawn")
        #expect(badgeText > 200, "the key badge's text is drawn")
        #expect(isPlain(early[2]), "no ripple yet at 0.5 s")

        let clicked = try await pixels(video, at: 1.2, [caption, badge, ripple])
        #expect(isPlain(clicked[0]), "caption gone at 1.2 s")
        #expect(clicked[1] < plain - 60, "key badge still shows at 1.2 s")
        #expect(clicked[2] > plain + 15, "ripple shows at 1.2 s")

        let late = try await pixels(video, at: 1.9, [caption, badge, ripple])
        #expect(late.allSatisfy(isPlain), "nothing left at 1.9 s")
    }

    @Test func withoutOverlaysTheTakeIsUntouched() async throws {
        let writer = TakeWriterTests()
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 1, audio: false, shade: 128)
        let take = Take(width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 1000, events: [])
        let output = Output(url: dir.appending(path: "out.mov"), format: .mov)
        try await Renderer.render(movie, take: take, overlays: [], to: output)
        let values = try await pixels(AVURLAsset(url: output.url), at: 0.5, [(x: width / 2, y: height - 10)])
        // 128 grey, give or take the export's colour conversion.
        #expect(abs(values[0] - 134) < 12)
    }

    /// The brightest point of one row of the frame at `time`, from `from` to `to`.
    private func brightest(_ asset: AVAsset, at time: Double, row: Int, from: Int, to: Int) async throws -> Int {
        try await pixels(asset, at: time, (from ..< to).map { (x: $0, y: row) }).max() ?? 0
    }

    /// The brightness (mean of red, green and blue) of each point, from the top left, in the frame at `time`.
    private func pixels(_ asset: AVAsset, at time: Double, _ points: [(x: Int, y: Int)]) async throws -> [Int] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return try points.map { point in
            try #require(point.x < image.width && point.y < image.height, "\(point) is outside the frame")
            let offset = (point.y * image.width + point.x) * 4
            return (Int(data[offset]) + Int(data[offset + 1]) + Int(data[offset + 2])) / 3
        }
    }
}

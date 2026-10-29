import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Writes a rendered movie as an endlessly looping GIF: frames sampled at `frameRate`, scaled to `width`, with
/// frames that look the same in a row merged into one longer frame, since a screen demo is mostly still and ImageIO
/// writes every frame in full.
public enum GifWriter {
    /// How far a channel may stray and still count as the same frame. A still window decodes with a little
    /// compression noise (measured up to 13 of 255); a real change, text or the cursor, moves channels by 100 and more.
    static let noise: UInt8 = 16

    public struct Result: Equatable, Sendable {
        public var frames: Int
        public var sampled: Int
    }

    @discardableResult
    public static func write(from movie: URL, to url: URL, frameRate: Int, width: Int) async throws -> Result {
        let asset = AVURLAsset(url: movie)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReelError("\(movie.path) has no picture")
        }
        let natural = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        let scaled = min(CGFloat(width), natural.width)
        let size = CGSize(width: scaled, height: (natural.height * scaled / natural.width).rounded())

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = size
        let count = max(1, Int((duration * Double(frameRate)).rounded(.down)))
        let times = (0 ..< count).map { CMTime(value: CMTimeValue($0), timescale: CMTimeScale(frameRate)) }

        // Each run of frames that look the same, with when it starts. Frames compare with the run's first, so slow
        // drift cannot add up unnoticed.
        var runs: [(image: CGImage, start: Double)] = []
        var kept: Data?
        for await result in generator.images(for: times) {
            let image = try result.image
            let pixels = image.dataProvider?.data as Data?
            if let pixels, let kept, looksTheSame(pixels, kept) { continue }
            runs.append((image, result.requestedTime.seconds))
            kept = pixels
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, runs.count, nil
        ) else {
            throw ReelError("cannot write \(url.path)")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        // GIF delays are hundredths of a second. Each frame runs from its start, rounded, to the next one's, rounded,
        // so the rounding never adds up.
        for (index, run) in runs.enumerated() {
            let end = index + 1 < runs.count ? runs[index + 1].start : duration
            let delay = Double(centiseconds(end) - centiseconds(run.start)) / 100
            CGImageDestinationAddImage(destination, run.image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ReelError("cannot write \(url.path)") }
        return Result(frames: runs.count, sampled: count)
    }

    static func looksTheSame(_ a: Data, _ b: Data, within tolerance: UInt8 = noise) -> Bool {
        guard a.count == b.count else { return false }
        return a.withUnsafeBytes { x in
            b.withUnsafeBytes { y in
                for index in 0 ..< x.count where x[index] &- y[index] > tolerance && y[index] &- x[index] > tolerance {
                    return false
                }
                return true
            }
        }
    }

    private static func centiseconds(_ seconds: Double) -> Int {
        Int((seconds * 100).rounded())
    }
}

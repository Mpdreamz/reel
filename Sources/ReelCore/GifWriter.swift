import AVFoundation
import Foundation
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
        public var bytes: Int
        /// What it was written with, after fitting.
        public var look = Look(frameRate: 15, width: 800, colors: 256)
        /// How many times it was written to fit under its size: 1 when it fit at once.
        public var writes = 1
    }

    /// How a GIF is drawn: `Set GifFrameRate`, `Set GifWidth`, `Set GifColors`.
    public struct Look: Equatable, Sendable {
        public var frameRate: Int
        public var width: Int
        public var colors: Int

        public init(frameRate: Int, width: Int, colors: Int) {
            self.frameRate = frameRate
            self.width = width
            self.colors = colors
        }

        /// The next, smaller look to try when one came out `ratio` times the size allowed: fewer colours first,
        /// which costs least to look at, then fewer frames, then a narrower picture. Far over (half again and more),
        /// it narrows as well: the cheap steps alone would not get there.
        func smaller(than ratio: Double) -> Look {
            var next = self
            // A GIF's size goes with its area: narrow by the square root of what it is over, and a little more.
            let narrower = max(GifWriter.narrowest, Int(Double(width) * (1 / ratio).squareRoot() * 0.95))
            if colors > 128 {
                next.colors = 128
            } else if colors > 64 {
                next.colors = 64
            } else if frameRate > 10 {
                next.frameRate = 10
            } else {
                next.width = narrower
            }
            if ratio >= 1.5 { next.width = narrower }
            return next
        }
    }

    static let narrowest = 160

    /// Writes the GIF as `look` says, and while it comes out over `maxBytes`, again smaller (`Look.smaller`); at
    /// most `tries` writes. Fails, removing the file, when nothing fits.
    public static func fit(from movie: URL, to url: URL, look: Look, under maxBytes: Int?, tries: Int = 6)
        async throws -> Result
    {
        var look = look
        var result = try await write(
            from: movie, to: url, frameRate: look.frameRate, width: look.width, colors: look.colors
        )
        guard let maxBytes else { return result }
        var writes = 1
        while result.bytes > maxBytes {
            guard writes < tries, look != look.smaller(than: Double(result.bytes) / Double(maxBytes)) else {
                try? FileManager.default.removeItem(at: url)
                throw ReelError(
                    "\(url.lastPathComponent) was still \(Encoder.megabytes(result.bytes)) after \(writes) writes, "
                        + "over MaxSize \(Encoder.megabytes(maxBytes)); try a lower Set GifWidth or a shorter take"
                )
            }
            look = look.smaller(than: Double(result.bytes) / Double(maxBytes))
            result = try await write(
                from: movie, to: url, frameRate: look.frameRate, width: look.width, colors: look.colors
            )
            writes += 1
        }
        result.writes = writes
        return result
    }

    @discardableResult
    public static func write(
        from movie: URL, to url: URL, frameRate: Int, width: Int, colors: Int = Tape.defaultGifColors
    ) async throws -> Result {
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

        // Fewer colours than a GIF holds: one palette for every frame, drawn in before ImageIO sees them.
        if colors < 256 {
            let palette = Palette(for: runs.map(\.image), count: colors)
            runs = runs.map { (palette.apply(to: $0.image) ?? $0.image, $0.start) }
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
        let bytes = fileSize(url)
        return Result(
            frames: runs.count, sampled: count, bytes: bytes,
            look: Look(frameRate: frameRate, width: Int(size.width), colors: colors)
        )
    }

    static func looksTheSame(_ a: Data, _ b: Data, within tolerance: UInt8 = noise) -> Bool {
        guard a.count == b.count else { return false }
        // Typed closures: without them newer SDKs find `withUnsafeBytes` ambiguous.
        return a.withUnsafeBytes { (x: UnsafeRawBufferPointer) -> Bool in
            b.withUnsafeBytes { (y: UnsafeRawBufferPointer) -> Bool in
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

import Foundation
import ImageIO
@testable import ReelCore
import Testing

/// GIFs written from generated takes, read back with ImageIO.
struct GifTests {
    let writer = TakeWriterTests()

    @Test func aStillTakeIsOneFrameForItsWholeLength() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 2, audio: false, shade: 128)
        let gif = dir.appending(path: "still.gif")
        let result = try await GifWriter.write(from: movie, to: gif, frameRate: 15, width: 800)
        #expect(result == GifWriter.Result(frames: 1, sampled: 30))
        let read = try GifFile(gif)
        #expect(read.delays == [2])
        #expect(read.loopCount == 0)
        // Never wider than the movie: 320 pixels.
        #expect(read.size == CGSize(width: 320, height: 200))
    }

    @Test func aChangingTakeKeepsEveryFrameAndItsTiming() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        // Half a second of fade: about 36 levels between sampled frames, well clear of the noise tolerance (16), so
        // scaling differences between machines cannot merge two of them.
        try await writer.writeTake(to: movie, seconds: 0.5, audio: false)
        let gif = dir.appending(path: "fade.gif")
        let result = try await GifWriter.write(from: movie, to: gif, frameRate: 15, width: 160)
        #expect(result.frames == 7)
        let read = try GifFile(gif)
        #expect(read.size == CGSize(width: 160, height: 100))
        // Frames start at k/15 s, rounded to hundredths (0, 7, 13, 20, 27, 33, 40) and the last runs to 50.
        #expect(read.delays == [0.07, 0.06, 0.07, 0.07, 0.06, 0.07, 0.10])
        #expect(abs(read.delays.reduce(0, +) - 0.5) < 0.001)
    }

    @Test func compressionNoiseIsTheSameFrameAndARealChangeIsNot() {
        let frame = Data((0 ..< 4000).map { UInt8($0 % 200 + 20) })
        var noisy = frame
        for index in stride(from: 0, to: noisy.count, by: 7) {
            noisy[index] = index % 2 == 0 ? noisy[index] + 13 : noisy[index] - 13
        }
        var changed = frame
        changed[1234] = changed[1234] &+ 120
        #expect(GifWriter.looksTheSame(frame, noisy))
        #expect(!GifWriter.looksTheSame(frame, changed))
        #expect(!GifWriter.looksTheSame(frame, frame.dropLast()))
    }

    @Test func aTapeWithOnlyAGifRendersThroughATemporaryMovie() async throws {
        let dir = try writer.temporaryDirectory()
        let location = TakeLocation(tape: dir.appending(path: "demo.tape"))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try await writer.writeTake(to: location.movie, seconds: 1, audio: false, shade: 90)
        try location.write(Take(
            width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 1000,
            events: [Take.Event(line: 4, command: "Sleep 1s", startMs: 0, endMs: 1000)]
        ))
        let tape = try Tape.parse("Output demo.gif\nLaunch x\nCaption \"Hi\"\nSleep 1s", relativeTo: dir)
        var lines: [String] = []
        try await Renderer.render(tape: tape, from: location, log: { lines.append($0) })
        let read = try GifFile(dir.appending(path: "demo.gif"))
        // The caption fades in and out over the still take, so more than one frame, and still a second long.
        #expect(read.delays.count > 1)
        #expect(abs(read.delays.reduce(0, +) - 1) < 0.001)
        #expect(lines.count == 1)
        #expect(lines[0].hasSuffix("demo.gif (\(read.delays.count) frames of 15 sampled)"))
    }
}

private struct GifFile {
    var size: CGSize
    var delays: [Double]
    var loopCount: Int?

    init(_ url: URL) throws {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        loopCount = (properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount]
            as? Int
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        size = CGSize(width: first.width, height: first.height)
        delays = (0 ..< CGImageSourceGetCount(source)).map { index in
            let frame = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
            return (delay * 100).rounded() / 100
        }
    }
}

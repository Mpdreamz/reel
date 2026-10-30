// Checks the take scripts/live.sh records of the fixture app: the window has the reel's size, the sound is silent
// until `Click "Play"` and a 440 Hz tone after it, and the fixture logged the click, the typing and the scroll.
//
// swift scripts/check-take.swift <take directory> <fixture-events.log> <rendered movie> <rendered gif>
import AVFoundation
import Foundation
import ImageIO

struct Take: Decodable {
    struct Event: Decodable {
        var command: String
        var startMs: Int
        var endMs: Int
        var x: Double?
        var w: Double?
        var clip: String?
    }

    var width: Int
    var height: Int
    var scale: Double
    var events: [Event]
    var durationMs: Int
    var cursor: [Sample]?
    var focus: [Sample]?

    struct Sample: Decodable {
        var ms: Int
    }
}

let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1])
let take = try JSONDecoder().decode(Take.self, from: Data(contentsOf: dir.appending(path: "take.json")))
let log = try String(contentsOf: URL(fileURLWithPath: args[2]), encoding: .utf8).split(separator: "\n").map(String.init)
var failed = false

func check(_ ok: Bool, _ what: String) {
    print(ok ? "✔ \(what)" : "✘ \(what)")
    if !ok { failed = true }
}

/// Mono samples at 48 kHz.
func samples(of url: URL) async throws -> [Float] {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
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

func rms(_ s: ArraySlice<Float>) -> Double {
    s.isEmpty ? 0 : (s.map { Double($0 * $0) }.reduce(0, +) / Double(s.count)).squareRoot()
}

func hertz(_ s: ArraySlice<Float>) -> Double {
    let crossings = zip(s.dropLast(), s.dropFirst()).count(where: { ($0 < 0) != ($1 < 0) })
    return Double(crossings) / 2 / (Double(s.count) / 48000)
}

check(take.width == Int(640 * take.scale), "the window is 640 points wide (\(take.width) pixels at \(take.scale)×)")
let click = take.events.first { $0.command == #"Click "Play""# }
check(click?.x != nil, "the timeline has where Click \"Play\" landed")
if let click {
    let sound = try await samples(of: dir.appending(path: "take.mov"))
    let before = sound.prefix(max(0, click.startMs - 50) * 48)
    let after = sound.dropFirst((click.endMs + 300) * 48).prefix(48000)
    check(!before.isEmpty && rms(before) < 0.002, String(format: "silent before the click (rms %.4f)", rms(before)))
    check(rms(after) > 0.05, String(format: "a tone after the click (rms %.3f)", rms(after)))
    check(abs(hertz(after) - 440) < 10, String(format: "at 440 Hz (%.0f)", hertz(after)))
}
let rendered = try await samples(of: URL(fileURLWithPath: args[3]))
if let gif = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[4]) as CFURL, nil),
   let first = CGImageSourceCreateImageAtIndex(gif, 0, nil)
{
    let frames = CGImageSourceGetCount(gif)
    let seconds = (0 ..< frames).reduce(0.0) { total, index in
        let properties = CGImageSourceCopyPropertiesAtIndex(gif, index, nil) as? [CFString: Any]
        let frame = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return total + (frame?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0)
    }
    let loop = ((CGImageSourceCopyProperties(gif, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary]
        as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int
    let movie = try await AVURLAsset(url: URL(fileURLWithPath: args[3])).load(.duration).seconds
    check(first.width == 800, "the GIF is 800 pixels wide (\(first.width))")
    check(abs(seconds - movie) < 0.1, String(format: "the GIF lasts as long as the movie (%.2f s of %.2f)", seconds, movie))
    check(loop == 0, "the GIF loops forever (\(frames) frames)")
} else {
    check(false, "the GIF can be read")
}
// Narration: in the rendered movie, timed by its markers, with the app's sound ducked under it.
let says = take.events.filter { $0.command.hasPrefix("Say") }
check(!says.isEmpty && says.allSatisfy { $0.clip != nil }, "every Say has its voiced line in the timeline")
func event(_ command: String) -> Take.Event? {
    take.events.first { $0.command == command }
}

/// How render mapped the take's time to the output's (edit.json next to the take).
struct Edit: Decodable {
    struct Segment: Decodable {
        var start: Double
        var end: Double
        var rate: Double
    }

    var segments: [Segment]

    func map(_ ms: Int) -> Int {
        let time = Double(ms) / 1000
        var out = 0.0
        for segment in segments {
            if time < segment.start { break }
            if time <= segment.end { return Int(((out + (time - segment.start) / segment.rate) * 1000).rounded()) }
            out += (segment.end - segment.start) / segment.rate
        }
        return Int((out * 1000).rounded())
    }
}

let edit = try JSONDecoder().decode(Edit.self, from: Data(contentsOf: dir.appending(path: "edit.json")))
// Where the demo starts in the finished movie: after the intro, less its transition.
let sections = (try? JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "sections.json"))))
    as? [String: Double]
let demoStart = Int(((sections?["demoStart"] ?? 0) * 1000).rounded())

/// The rendered sound between two moments of the take.
func window(_ from: Int, _ to: Int) -> ArraySlice<Float> {
    let start = (demoStart + edit.map(from)) * 48, end = (demoStart + edit.map(to)) * 48
    return rendered[min(rendered.count, max(0, start)) ..< min(rendered.count, max(start, end))]
}

func level(_ samples: ArraySlice<Float>, _ hertz: Double) -> Double {
    let k = 2 * cos(2 * .pi * hertz / 48000)
    var s1 = 0.0, s2 = 0.0
    for x in samples {
        (s1, s2) = (Double(x) + k * s1 - s2, s1)
    }
    return samples.isEmpty ? 0 : 2 * (s1 * s1 + s2 * s2 - k * s1 * s2).squareRoot() / Double(samples.count)
}

// The demo's own length, before the intro and the outro are put around it.
let edited = edit.segments.reduce(0.0) { $0 + ($1.end - $1.start) / $1.rate }
let taken = Double(take.durationMs) / 1000
check(edited < taken - 1.2, String(format: "Hide and Speed shortened the demo (%.2f s of a %.2f s take)", edited, taken))

let tail = window(take.durationMs - 1500, take.durationMs - 700)
check(rms(tail) > 0.05 && abs(hertz(tail) - 440) < 10, "the rendered demo keeps the tone, overlays and all")

// The intro and the outro: their backgrounds at the movie's corners, before and after the demo.
func corner(at seconds: Double) async throws -> (Int, Int, Int) {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: args[3])))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image.cropping(to: CGRect(x: 8, y: 8, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
}

let movieLength = try await AVURLAsset(url: URL(fileURLWithPath: args[3])).load(.duration).seconds
let opening = try await corner(at: 0.8)
let closing = try await corner(at: movieLength - 0.3)
check(demoStart > 1000, "the demo starts after the intro (\(demoStart) ms in)")
check(opening.0 < 40 && opening.1 < 40 && opening.2 < 40, "the intro shows its dark background \(opening)")
// #1d2b3a: 29, 43, 58.
check(abs(closing.0 - 29) < 14 && abs(closing.1 - 43) < 14 && abs(closing.2 - 58) < 14,
      "the outro shows its navy background \(closing)")

if let intro = event(#"Say "This is the reel fixture.""#) {
    let speech = rms(window(intro.startMs, intro.endMs))
    check(speech > 0.02, String(format: "the narration is in the rendered movie (rms %.3f)", speech))
}
if let over = event(#"Say@over "Now click [play] Play, and a tone starts.""#), let wait = event("Wait [play]") {
    check(wait.endMs - over.startMs > 250, "Click waits for [play], \(wait.endMs - over.startMs) ms into the line")
}
if let under = event(#"Say "The tone keeps playing under the voice.""#) {
    let during = level(window(under.startMs + 300, under.endMs - 300), 440)
    let after = level(window(under.endMs + 400, under.endMs + 900), 440)
    check(
        after > 0.02 && during / after < 0.4,
        String(format: "the tone ducks under the voice (%.0f%% of its level after)", 100 * during / max(after, 1e-9))
    )
}
// Zoom, speed and trim.
// An element zoom's timeline names the element alone (its scale and easing are render's).
let zoomed = event("Zoom #list")
check(zoomed?.w != nil, "Zoom #list found the list's frame while recording")
check((take.focus?.count ?? 0) >= 2, "the locked list was sampled after each step (\(take.focus?.count ?? 0) samples)")
check((take.cursor?.count ?? 0) > take.durationMs / 50, "the cursor was sampled through the take (\(take.cursor?.count ?? 0))")

check(log.contains("play"), "the fixture logged the click on Play")
check(log.contains("submit Musicbox"), "cmd+a replaced the typed text, and return submitted it")
check(log.contains { $0.hasPrefix("scroll ") && Int($0.dropFirst(7)).map { $0 > 0 } == true }, "the list scrolled")
exit(failed ? 1 : 0)

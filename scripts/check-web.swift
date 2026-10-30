// Checks the take scripts/live-web.sh records of reels/web/fixture.html: the page's size, its sound (silent until
// Click "Play", a 440 Hz tone after), the drawn cursor's path, and the rendered movie. That each step did what it
// should, the reel itself waited for.
//
// swift scripts/check-web.swift <take directory> <rendered movie>
import AVFoundation
import Foundation

struct Take: Decodable {
    struct Event: Decodable {
        var command: String
        var startMs: Int
        var endMs: Int
    }

    struct Sample: Decodable {
        var ms: Int
        var x: Double
        var y: Double
    }

    var width: Int
    var height: Int
    var scale: Double
    var events: [Event]
    var cursor: [Sample]?
    var drawnCursor: Bool?
}

let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1])
let take = try JSONDecoder().decode(Take.self, from: Data(contentsOf: dir.appending(path: "take.json")))
var failed = false

func check(_ ok: Bool, _ what: String) {
    print(ok ? "✔ \(what)" : "✘ \(what)")
    if !ok { failed = true }
}

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

check(take.width == Int(1000 * take.scale), "the page is 1000 points wide (\(take.width) pixels at \(take.scale)×)")
check(take.height == Int(700 * take.scale), "and 700 high, the title bar cropped off (\(take.height))")
check(take.drawnCursor == true, "the take asks render to draw the cursor")
check((take.cursor?.count ?? 0) > 50, "the cursor's path was kept (\(take.cursor?.count ?? 0) points)")
if let click = take.events.first(where: { $0.command == #"Click "Play""# }) {
    let sound = try await samples(of: dir.appending(path: "take.mov"))
    let before = sound.prefix(max(0, click.startMs - 50) * 48)
    let after = sound.dropFirst((click.endMs + 400) * 48).prefix(48000)
    check(!before.isEmpty && rms(before) < 0.002, String(format: "silent before the click (rms %.4f)", rms(before)))
    check(rms(after) > 0.03, String(format: "the page's tone after it (rms %.3f)", rms(after)))
    check(abs(hertz(after) - 440) < 10, String(format: "at 440 Hz (%.0f)", hertz(after)))
} else {
    check(false, #"the take has Click "Play""#)
}
let movie = AVURLAsset(url: URL(fileURLWithPath: args[2]))
check(try await movie.load(.duration).seconds > 3, "the movie was rendered")
exit(failed ? 1 : 0)

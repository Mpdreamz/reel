// Checks the take scripts/live.sh records of the fixture app: the window has the tape's size, the sound is silent
// until `Click "Play"` and a 440 Hz tone after it, and the fixture logged the click, the typing and the scroll.
//
// swift scripts/check-take.swift <take directory> <fixture-events.log> <rendered output>
import AVFoundation
import Foundation

struct Take: Decodable {
    struct Event: Decodable {
        var command: String
        var startMs: Int
        var endMs: Int
        var x: Double?
    }

    var width: Int
    var height: Int
    var scale: Double
    var events: [Event]
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
let tail = rendered.dropFirst(max(0, rendered.count - 48000))
check(rms(tail) > 0.05 && abs(hertz(tail) - 440) < 10, "the rendered output keeps the tone, overlays and all")
check(log.contains("play"), "the fixture logged the click on Play")
check(log.contains("submit Musicbox"), "cmd+a replaced the typed text, and return submitted it")
check(log.contains { $0.hasPrefix("scroll ") && Int($0.dropFirst(7)).map { $0 > 0 } == true }, "the list scrolled")
exit(failed ? 1 : 0)

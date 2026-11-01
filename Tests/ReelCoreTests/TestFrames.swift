import AVFoundation
import Foundation
import Testing

/// A movie's frames as BGRA bytes, as written (no frame for a still screen).
func movieFrames(_ asset: AVAsset) async throws -> [Data] {
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    reader.add(output)
    reader.startReading()
    var all: [Data] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let length = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
        all.append(Data(bytes: CVPixelBufferGetBaseAddress(buffer)!, count: length))
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    }
    return all
}

/// The mean difference of each byte, out of 255.
func frameDifference(_ a: Data, _ b: Data) -> Double {
    guard a.count == b.count else { return 255 }
    var total = 0
    a.withUnsafeBytes { x in
        b.withUnsafeBytes { y in
            for i in 0 ..< a.count {
                total += abs(Int(x[i]) - Int(y[i]))
            }
        }
    }
    return Double(total) / Double(a.count)
}

import AVFoundation
import CoreMedia
@testable import ReelCore
import Testing

/// The writer and the render on generated frames and a sine tone: what capture hands them, without needing Screen
/// Recording.
struct TakeWriterTests {
    let width = 320, height = 200, fps = 30

    @Test func takeKeepsPictureAndSoundThroughRender() async throws {
        let dir = try temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writeTake(to: movie, seconds: 1, audio: true)

        let asset = AVURLAsset(url: movie)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await video.load(.naturalSize) == CGSize(width: width, height: height))
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await abs(asset.load(.duration).seconds - 1) < 0.1)

        for format in Output.Format.allCases where format != .gif {
            let url = dir.appending(path: "demo.\(format.rawValue)")
            try await Renderer.render(
                movie, take: take(seconds: 1), overlays: [], soundtrack: .none, to: Output(url: url, format: format)
            )
            let rendered = AVURLAsset(url: url)
            #expect(try await !rendered.loadTracks(withMediaType: .video).isEmpty)
            #expect(try await abs(rendered.load(.duration).seconds - 1) < 0.1)
            // The tone is at 0.5 amplitude, so about 0.35 RMS; silence would be 0.
            #expect(try await rms(of: rendered) > 0.2)
        }
    }

    @Test func noSoundWhenAudioIsOff() async throws {
        let movie = try temporaryDirectory().appending(path: "take.mov")
        try await writeTake(to: movie, seconds: 0.5, audio: false)
        #expect(try await AVURLAsset(url: movie).loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func soundBeforeTheFirstFrameIsDropped() async throws {
        let movie = try temporaryDirectory().appending(path: "take.mov")
        let writer = try TakeWriter(
            url: movie, width: width, height: height, frameRate: fps, audio: true, realTime: false
        )
        await writer.onQueue {
            writer.append(audio: tone(at: CMTime(value: 0, timescale: 48000), frames: 48000))
            writer.append(video: frame(at: CMTime(value: 2, timescale: 1), shade: 0))
        }
        try await writer.finish(at: CMTime(value: 3, timescale: 1))
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1) < 0.05)
        #expect(try await rms(of: asset) == 0)
    }

    @Test func aTakeWithoutFramesFails() async throws {
        let movie = try temporaryDirectory().appending(path: "take.mov")
        let writer = try TakeWriter(url: movie, width: width, height: height, frameRate: fps, audio: true)
        await #expect(throws: ReelError.self) { try await writer.finish(at: .zero) }
    }

    @Test func timelineRoundTrips() throws {
        let location = try TakeLocation(tape: temporaryDirectory().appending(path: "demo.tape"))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: location.movie.path, contents: Data())
        let take = Take(
            width: 640, height: 400, scale: 2, frameRate: 60, audio: true, durationMs: 2500,
            events: [Take.Event(line: 4, command: "Sleep 2s", startMs: 0, endMs: 2001)]
        )
        try location.write(take)
        #expect(try location.read() == take)
    }

    @Test func renderWithoutATakeSaysSo() throws {
        let location = try TakeLocation(tape: temporaryDirectory().appending(path: "demo.tape"))
        #expect(throws: ReelError.self) { try location.read() }
    }

    // MARK: Generated media

    private func take(seconds: Double, events: [Take.Event] = []) -> Take {
        Take(
            width: width, height: height, scale: 1, frameRate: fps, audio: false,
            durationMs: Int(seconds * 1000), events: events
        )
    }

    /// Frames at `fps` that fade from black to white, and the sound as 100 ms chunks of a 440 Hz tone, interleaved
    /// the way capture delivers them.
    func writeTake(to url: URL, seconds: Double, audio: Bool, shade fixed: UInt8? = nil) async throws {
        let writer = try TakeWriter(
            url: url, width: width, height: height, frameRate: fps, audio: audio, realTime: false
        )
        let frames = Int(seconds * Double(fps))
        let chunk = 4800
        await writer.onQueue {
            var sent = 0
            for i in 0 ..< frames {
                let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
                writer.append(video: frame(at: time, shade: fixed ?? UInt8(i * 255 / max(1, frames - 1))))
                // Sound runs 0.2 s ahead of the picture, as capture delivers it: the writer holds the picture back
                // until the sound has caught up, so sound that lags would leave both waiting.
                while audio, Double(sent) / 48000 < time.seconds + 0.2, Double(sent) / 48000 < seconds {
                    writer.append(audio: tone(at: CMTime(value: CMTimeValue(sent), timescale: 48000), frames: chunk))
                    sent += chunk
                }
            }
        }
        try await writer.finish(at: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    private func frame(at time: CMTime, shade: UInt8) -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels
        )
        let buffer = pixels!
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), Int32(shade), CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(fps)), presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: format!, sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        return sample!
    }

    /// Interleaved stereo Float32 at 48 kHz, a 440 Hz sine at half amplitude.
    private func tone(at time: CMTime, frames: Int) -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format
        )
        let start = Int(time.value)
        var samples = [Float](repeating: 0, count: frames * 2)
        for i in 0 ..< frames {
            let value = Float(0.5 * sin(2 * Double.pi * 440 * Double(start + i) / 48000))
            samples[2 * i] = value
            samples[2 * i + 1] = value
        }
        let length = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        samples.withUnsafeBytes {
            _ = CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: length
            )
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: frames,
            presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &sample
        )
        return sample!
    }

    /// The root mean square of every sample in the asset's sound; 0 when it has none.
    private func rms(of asset: AVAsset) async throws -> Double {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        reader.startReading()
        var sum = 0.0, count = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            floats.withUnsafeMutableBytes {
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            for value in floats {
                sum += Double(value * value)
            }
            count += floats.count
        }
        return count == 0 ? 0 : (sum / Double(count)).squareRoot()
    }

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "reel-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension TakeWriter {
    /// Runs `work` on the writer's queue and waits for it without blocking a thread of Swift's pool: writing a take
    /// waits on the encoder, and tests running in parallel that each block a pool thread can starve the rest.
    func onQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                work()
                done.resume()
            }
        }
    }
}

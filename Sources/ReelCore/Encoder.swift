import AVFoundation
import CoreMedia

/// How a movie Output is compressed: `Set Quality`, `Set Codec` and `Set VideoWidth`.
public struct Encoding: Equatable, Sendable {
    public enum Codec: String, Equatable, Sendable, CaseIterable {
        /// Plays everywhere, browsers included.
        case h264
        /// About half the size at the same quality; plays on Apple devices and in most current browsers.
        case hevc
    }

    /// 1–100: the encoder's own quality scale, not a bitrate. Screen recordings are mostly still, so the size follows
    /// how much moves as much as this.
    public var quality: Int
    public var codec: Codec
    /// Pixels wide, scaled down from the rendered size (never up); nil keeps it, Retina pixels and all.
    public var width: Int?

    public static let defaultQuality = 65
    public static let standard = Encoding(quality: defaultQuality, codec: .h264, width: nil)

    public init(quality: Int, codec: Codec, width: Int?) {
        self.quality = quality
        self.codec = codec
        self.width = width
    }

    /// The size a movie of `natural` size is written at: `width` when it is narrower, the height kept in proportion;
    /// both even, as the encoders want them.
    public func size(for natural: CGSize) -> CGSize {
        let width = min(CGFloat(width ?? Int(natural.width)), natural.width)
        func even(_ value: CGFloat) -> CGFloat {
            max(2, CGFloat(Int(value.rounded()) & ~1))
        }
        return CGSize(width: even(width), height: even(natural.height * width / natural.width))
    }
}

/// Compresses a rendered (lossless) movie into an Output as its `Encoding` says: the picture as H.264 or HEVC at a
/// quality, scaled down when asked, and the sound as AAC.
public enum Encoder {
    public struct Result: Equatable, Sendable {
        public var size: CGSize
        public var bytes: Int
    }

    @discardableResult
    public static func encode(_ movie: URL, to output: Output, with encoding: Encoding, frameRate: Int)
        async throws -> Result
    {
        precondition(output.format != .gif, "a GIF is written by GifWriter")
        let asset = AVURLAsset(url: movie)
        guard let picture = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReelError("\(movie.path) has no picture")
        }
        let sounds = try await asset.loadTracks(withMediaType: .audio)
        let natural = try await picture.load(.naturalSize)
        let size = encoding.size(for: natural)

        let reader = try AVAssetReader(asset: asset)
        // The size is asked of the decoder, which scales as it decodes.
        let frames = AVAssetReaderTrackOutput(track: picture, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        frames.alwaysCopiesSampleData = false
        reader.add(frames)
        // Every sound track mixed into one stereo track, as the encoder below takes it.
        let samples = sounds.isEmpty ? nil : AVAssetReaderAudioMixOutput(audioTracks: sounds, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        if let samples { reader.add(samples) }

        try FileManager.default.createDirectory(
            at: output.url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: output.url)
        let writer = try AVAssetWriter(outputURL: output.url, fileType: output.format == .mp4 ? .mp4 : .mov)
        // The index at the front, so a browser starts playing before the whole file is in.
        writer.shouldOptimizeForNetworkUse = true
        var compression: [String: Any] = [
            AVVideoQualityKey: Double(encoding.quality) / 100,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            // A keyframe every two seconds, for seeking.
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
        ]
        if encoding.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: encoding.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ])
        video.expectsMediaDataInRealTime = false
        writer.add(video)
        let audio = samples.map { _ in
            AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
        }
        if let audio {
            audio.expectsMediaDataInRealTime = false
            writer.add(audio)
        }

        guard reader.startReading() else {
            throw ReelError("cannot read \(movie.path): \(reader.error?.localizedDescription ?? "unknown error")")
        }
        guard writer.startWriting() else {
            throw ReelError("cannot write \(output.url.path): \(writer.error?.localizedDescription ?? "unknown error")")
        }
        writer.startSession(atSourceTime: .zero)
        let picturePump = Pump(output: frames, input: video)
        let soundPump = samples.flatMap { samples in audio.map { Pump(output: samples, input: $0) } }
        async let pictureDone: Void = picturePump.run()
        await soundPump?.run()
        await pictureDone

        if reader.status == .failed {
            writer.cancelWriting()
            throw ReelError("cannot read \(movie.path): \(reader.error?.localizedDescription ?? "unknown error")")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ReelError("cannot write \(output.url.path): \(writer.error?.localizedDescription ?? "unknown error")")
        }
        let bytes = (try? output.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Result(size: size, bytes: bytes)
    }
}

/// A reader output and a writer input, only ever touched on `queue`, which is what makes the unchecked `Sendable`
/// hold.
private final class Pump: @unchecked Sendable {
    let queue = DispatchQueue(label: "reel.encoder")
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private var finished = false

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput) {
        self.output = output
        self.input = input
    }

    /// Feeds the output's samples into the input as fast as it takes them, and returns once they run out (or the
    /// input stops taking them).
    func run() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) { self.drain(then: done) }
        }
    }

    private func drain(then done: CheckedContinuation<Void, Never>) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished else { return }
        while input.isReadyForMoreMediaData {
            guard let buffer = output.copyNextSampleBuffer(), input.append(buffer) else {
                input.markAsFinished()
                finished = true
                done.resume()
                return
            }
        }
    }
}

import AVFoundation
import CoreMedia
import VideoToolbox

/// How a movie Output is compressed: `Set Quality`, `Set Codec` and `Set VideoWidth`.
public struct Encoding: Equatable, Sendable {
    public enum Codec: String, Equatable, Sendable, CaseIterable {
        /// Plays everywhere, browsers included.
        case h264
        /// About half the size at the same quality; plays on Apple devices and in most current browsers.
        case hevc
        /// ProRes 422 and PCM sound: lossless for editing, and large. Only a `.mov` holds it; an `.mp4` gets H.264
        /// at quality 100 instead.
        case prores
    }

    /// 1–100: the encoder's own quality scale, not a bitrate. Screen recordings are mostly still, so the size follows
    /// how much moves as much as this.
    public var quality: Int
    public var codec: Codec
    /// Pixels wide, scaled down from the rendered size (never up); nil keeps it, Retina pixels and all.
    public var width: Int?
    /// Frames a second, at most the movie's own (`Set VideoFrameRate`); nil keeps the movie's.
    public var frameRate: Int?
    /// Bits a second, in place of the quality: how a movie is fitted under a size (`Set MaxSize`).
    public var bitrate: Int?

    public static let defaultQuality = 65
    public static let standard = Encoding(quality: defaultQuality, codec: .h264, width: nil)

    public init(quality: Int, codec: Codec, width: Int?, frameRate: Int? = nil, bitrate: Int? = nil) {
        self.quality = quality
        self.codec = codec
        self.width = width
        self.frameRate = frameRate
        self.bitrate = bitrate
    }

    /// What `format` can hold of this: ProRes only goes in a `.mov`; an `.mp4` gets H.264 at quality 100.
    public func fitting(_ format: Output.Format) -> Encoding {
        guard codec == .prores, format == .mp4 else { return self }
        var encoding = self
        encoding.codec = .h264
        encoding.quality = 100
        return encoding
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
        /// What the movie was written with, after fitting.
        public var encoding: Encoding
        /// How many times it was encoded to fit under its size: 1 when it fit at once.
        public var encodes = 1
    }

    /// The bits a pixel a frame below which a screen recording smears: fitting a size lowers the frame rate to 30,
    /// then narrows the picture, rather than go under it. A demo is mostly still, so it needs few.
    static let leanest = 0.005
    /// Fitting takes a movie down to this many frames a second before it narrows it.
    static let fittedFrameRate = 30
    static let soundBitrate = 192_000
    /// The narrowest fitting makes a movie.
    static let narrowest = 640

    /// Encodes as `encoding` says, and when the movie comes out over `maxBytes`, again at the bitrate that size
    /// leaves for its length, correcting by how far each try missed; at most `tries` encodes. The picture narrows
    /// when the bitrate would be too lean for its size. Fails, removing the file, when nothing fits.
    public static func fit(
        _ movie: URL, to output: Output, with encoding: Encoding, frameRate: Int, under maxBytes: Int?,
        tries: Int = 4
    ) async throws -> Result {
        var result = try await encode(movie, to: output, with: encoding, frameRate: frameRate)
        guard let maxBytes, result.bytes > maxBytes else { return result }
        let asset = AVURLAsset(url: movie)
        let seconds = try await asset.load(.duration).seconds
        let sound = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        let natural = try await asset.loadTracks(withMediaType: .video).first?.load(.naturalSize) ?? result.size
        // A little under the limit: the container's own bytes, and the encoder's aim, are not exact.
        let budget = Double(maxBytes) * 8 * 0.95 - (sound ? Double(soundBitrate) * seconds : 0)
        guard seconds > 0, budget > 0 else {
            try? FileManager.default.removeItem(at: output.url)
            throw ReelError(
                "\(output.url.lastPathComponent) cannot fit \(megabytes(maxBytes)): its sound alone fills it"
            )
        }
        var fitted = encoding.fitting(output.format)
        if fitted.codec == .prores { fitted.codec = .h264 }
        var bitrate = budget / seconds
        // What each try came out at, to aim the next one through the last two: a busy picture has a floor its size
        // will not go under, so the size does not follow the bitrate down in proportion.
        var tried: [(bitrate: Double, bytes: Double)] = []
        let target = Double(maxBytes) * 0.95
        // The best that fit so far, when it left much of the size unused: a still picture spends less than it may.
        var roomy: (encoding: Encoding, result: Result)?
        for attempt in 2 ... max(2, tries) {
            var size = fitted.size(for: natural)
            func lean() -> Bool {
                bitrate / (size.width * size.height * Double(min(fitted.frameRate ?? frameRate, frameRate))) < leanest
            }
            if lean(), min(fitted.frameRate ?? frameRate, frameRate) > fittedFrameRate {
                fitted.frameRate = fittedFrameRate
            }
            while lean(), Int(size.width) > narrowest {
                fitted.width = max(narrowest, Int(size.width * 0.8))
                size = fitted.size(for: natural)
            }
            // Below this the encoder refuses, and nothing worth watching is left anyway.
            guard bitrate >= 50000 else { break }
            fitted.bitrate = Int(bitrate)
            result = try await encode(movie, to: output, with: fitted, frameRate: frameRate)
            result.encodes = attempt
            if result.bytes <= maxBytes {
                // Well under, with tries to spare: once more, richer, keeping this one should that not fit.
                guard result.bytes < maxBytes * 7 / 10, roomy == nil, attempt < tries else { return result }
                roomy = (fitted, result)
                bitrate *= min(2, target / Double(result.bytes))
                continue
            }
            if let roomy {
                // The richer try went over: the one before it is the answer.
                var kept = try await encode(movie, to: output, with: roomy.encoding, frameRate: frameRate)
                kept.encodes = attempt + 1
                return kept
            }
            tried.append((bitrate, Double(result.bytes)))
            var next = bitrate * target / Double(result.bytes)
            if tried.count >= 2 {
                let (a, b) = (tried[tried.count - 2], tried[tried.count - 1])
                if b.bytes != a.bytes, b.bitrate != a.bitrate {
                    let slope = (b.bytes - a.bytes) / (b.bitrate - a.bitrate)
                    if slope > 0 { next = b.bitrate + (target - b.bytes) / slope }
                }
            }
            // Never more than proportion asks, and never a leap below a quarter.
            bitrate = min(bitrate * target / Double(result.bytes), max(bitrate / 4, next))
        }
        if let roomy { return roomy.result }
        try? FileManager.default.removeItem(at: output.url)
        throw ReelError(
            "\(output.url.lastPathComponent) was still \(megabytes(result.bytes)) after \(result.encodes) encodes, over "
                + "MaxSize \(megabytes(maxBytes)); try a lower Set VideoWidth or Set VideoFrameRate, or a shorter take"
        )
    }

    static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    @discardableResult
    public static func encode(_ movie: URL, to output: Output, with requested: Encoding, frameRate: Int)
        async throws -> Result
    {
        precondition(output.format != .gif, "a GIF is written by GifWriter")
        let encoding = requested.fitting(output.format)
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
            AVVideoExpectedSourceFrameRateKey: min(encoding.frameRate ?? frameRate, frameRate),
            // A keyframe every two seconds, for seeking.
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
        ]
        if let bitrate = encoding.bitrate {
            compression[AVVideoAverageBitRateKey] = bitrate
            // The average alone is a hope: on busy pictures the encoder runs well over it. A hard cap over each
            // second holds it to the size.
            compression[kVTCompressionPropertyKey_DataRateLimits as String] = [bitrate / 8, 1] as [Int]
        } else {
            compression[AVVideoQualityKey] = Double(encoding.quality) / 100
        }
        if encoding.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        var settings: [String: Any] = [
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        switch encoding.codec {
        case .h264: settings[AVVideoCodecKey] = AVVideoCodecType.h264
        case .hevc: settings[AVVideoCodecKey] = AVVideoCodecType.hevc
        case .prores: settings[AVVideoCodecKey] = AVVideoCodecType.proRes422
        }
        // ProRes takes no compression settings: it has one quality.
        if encoding.codec != .prores { settings[AVVideoCompressionPropertiesKey] = compression }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = false
        writer.add(video)
        let audio = samples.map { _ in
            AVAssetWriterInput(mediaType: .audio, outputSettings: encoding.codec == .prores ? [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ] : [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: soundBitrate,
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
        // Fewer frames a second than the movie's: each kept frame lasts until the next one.
        let keep = encoding.frameRate.flatMap { $0 < frameRate ? $0 : nil }
        let picturePump = Pump(output: frames, input: video, frameRate: keep)
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
        removeLeftovers(of: output.url)
        let bytes = fileSize(output.url)
        return Result(size: size, bytes: bytes, encoding: encoding)
    }
}

/// A reader output and a writer input, only ever touched on `queue`, which is what makes the unchecked `Sendable`
/// hold.
private final class Pump: @unchecked Sendable {
    let queue = DispatchQueue(label: "reel.encoder")
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private var finished = false
    /// With a frame rate, only the first frame in each of its slots is kept.
    private let frameRate: Int?
    private var lastSlot = Int.min

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, frameRate: Int? = nil) {
        self.output = output
        self.input = input
        self.frameRate = frameRate
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
            let next = output.copyNextSampleBuffer()
            if let next, let frameRate {
                let time = CMSampleBufferGetPresentationTimeStamp(next).seconds
                let slot = Int((time * Double(frameRate) + 0.001).rounded(.down))
                if slot <= lastSlot { continue }
                lastSlot = slot
            }
            guard let buffer = next, input.append(buffer) else {
                input.markAsFinished()
                finished = true
                done.resume()
                return
            }
        }
    }
}

/// Bytes in the file at `url`, as it is now: `URL.resourceValues` keeps what it read first, so a file written again
/// under the same URL would read as its first size.
func fileSize(_ url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
}

/// Removes the file AVFoundation writes a movie through when it moves the index to the front (`name.mp4.sb-…`, the
/// data first). The movie is complete by now; AVFoundation would remove it only once the writer goes, which the last
/// movie a run writes does not live to see.
func removeLeftovers(of url: URL) {
    let folder = url.deletingLastPathComponent()
    let prefix = url.lastPathComponent + ".sb-"
    for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(prefix) {
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }
}

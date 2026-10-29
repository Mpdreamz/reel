import AVFoundation
import CoreMedia

/// Writes captured frames and sound to `take.mov`: H.264 at a bitrate high enough to render from, AAC for the sound.
/// The movie starts at the first frame; sound from before it is not in it.
///
/// Every `append` must run on `queue` (ScreenCaptureKit delivers both kinds of buffer there), which is what makes
/// the unchecked `Sendable` hold.
public final class TakeWriter: @unchecked Sendable {
    public let queue = DispatchQueue(label: "reel.take-writer")
    public private(set) var firstFrameTime: CMTime?
    public private(set) var lastFrameTime: CMTime?
    public private(set) var droppedFrames = 0

    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private let realTime: Bool
    private let frameInterval: CMTime
    private var lastFrame: CMSampleBuffer?

    /// - Parameter realTime: capture drops a frame the encoder is not ready for; anything else (tests, later
    ///   offline passes) waits for it.
    public init(url: URL, width: Int, height: Int, frameRate: Int, audio withAudio: Bool, realTime: Bool = true)
        throws
    {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        self.realTime = realTime
        frameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        // About 0.2 bits a pixel a frame: generous for screen content, which is mostly still.
        let bitrate = max(4_000_000, Int(Double(width * height * frameRate) * 0.2))
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        video.expectsMediaDataInRealTime = realTime
        writer.add(video)

        if withAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = realTime
            writer.add(input)
            audio = input
        } else {
            audio = nil
        }

        guard writer.startWriting() else {
            throw ReelError("cannot write \(url.path): \(writer.error?.localizedDescription ?? "unknown error")")
        }
    }

    public func append(video buffer: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        if firstFrameTime == nil {
            writer.startSession(atSourceTime: time)
            firstFrameTime = time
        }
        guard ready(video) else {
            droppedFrames += 1
            return
        }
        if video.append(buffer) {
            lastFrameTime = time
            lastFrame = buffer
        }
    }

    public func append(audio buffer: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        // Nothing may be appended before the session starts at the first frame; the writer trims sound from
        // before it.
        guard let audio, firstFrameTime != nil, ready(audio) else { return }
        audio.append(buffer)
    }

    /// Ends the movie at `time` and waits for the file to be complete. A still window sends no new frames, so the
    /// last frame is repeated just before `time`: a frame only lasts its own duration, and without it the movie
    /// would end where the window stopped changing.
    public func finish(at time: CMTime) async throws {
        let writer = writer
        let end: CMTime? = await withCheckedContinuation { done in
            queue.async { [self] in
                guard firstFrameTime != nil else { return done.resume(returning: nil) }
                holdLastFrame(until: time)
                video.markAsFinished()
                audio?.markAsFinished()
                done.resume(returning: max(time, lastFrameTime ?? time))
            }
        }
        guard let end else {
            writer.cancelWriting()
            throw ReelError("no frame was captured")
        }
        writer.endSession(atSourceTime: end)
        await writer.finishWriting()
        if writer.status != .completed {
            throw ReelError("writing the take failed: \(writer.error?.localizedDescription ?? "unknown error")")
        }
    }

    private func holdLastFrame(until end: CMTime) {
        guard let lastFrame, let lastFrameTime, end - frameInterval > lastFrameTime else { return }
        var timing = CMSampleTimingInfo(
            duration: frameInterval, presentationTimeStamp: end - frameInterval, decodeTimeStamp: .invalid
        )
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: lastFrame, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        // Waits even when capturing (a little): this is the one frame the movie cannot do without.
        let deadline = Date().addingTimeInterval(2)
        while !video.isReadyForMoreMediaData, writer.status == .writing, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        if let copy, video.append(copy) { self.lastFrameTime = end - frameInterval }
    }

    /// Without real time, waits for `input`, but not forever: the writer holds one input back until the other
    /// catches up, so a caller that feeds them out of step would wait for good. Giving up drops the buffer, which
    /// `droppedFrames` and the movie's length show.
    private func ready(_ input: AVAssetWriterInput) -> Bool {
        if realTime { return input.isReadyForMoreMediaData }
        let deadline = Date().addingTimeInterval(2)
        while !input.isReadyForMoreMediaData, writer.status == .writing, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        return input.isReadyForMoreMediaData && writer.status == .writing
    }
}

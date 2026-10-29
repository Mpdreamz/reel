import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// How a recording is framed on a canvas: its size, where the recording sits on it (with rounded corners and a soft
/// shadow), and what fills the rest. Pixels, from the canvas's top left.
public struct Framing: Equatable, Sendable {
    public var canvas: CGSize
    public var content: CGRect
    /// The recording's corner radius, in canvas pixels.
    public var corner: Double
    public var background: Background

    /// Room around the recording, as a share of the canvas's shorter side.
    public static let defaultPadding = 0.06
    /// A window's corner radius, in points.
    static let windowCorner = 12.0
    /// No canvas is worked out wider or taller than this; an exact size may be.
    static let longestSide = 3840.0

    /// Frames a recording of `recording` pixels (at `scale` pixels a point) on a canvas of `shape`, or of the
    /// recording's own shape with `padding` around it. At an aspect, the canvas is the smallest that holds the
    /// recording at its own size with the padding, shrunk to `longestSide`; an exact size fits the recording in.
    public static func make(
        recording: CGSize, scale: Double, shape: Output.Shape?, padding: Double, background: Background
    ) -> Framing {
        let p = padding
        var canvas: CGSize
        switch shape {
        case nil:
            // Padding is a share of the canvas's shorter side, which the padding itself makes longer.
            let pad = p * min(recording.width, recording.height) / (1 - 2 * p)
            canvas = CGSize(width: recording.width + 2 * pad, height: recording.height + 2 * pad)
        case let .aspect(w, h):
            let a = Double(w) / Double(h)
            // The least height whose canvas, less its padding, holds the recording.
            let height = a >= 1
                ? max(recording.width / (a - 2 * p), recording.height / (1 - 2 * p))
                : max(recording.width / (a * (1 - 2 * p)), recording.height / (1 - 2 * p * a))
            canvas = CGSize(width: a * height, height: height)
        case let .size(w, h):
            canvas = CGSize(width: w, height: h)
        }
        if case .size = shape {} else if max(canvas.width, canvas.height) > longestSide {
            let shrink = longestSide / max(canvas.width, canvas.height)
            canvas = CGSize(width: canvas.width * shrink, height: canvas.height * shrink)
        }
        canvas = CGSize(width: even(canvas.width), height: even(canvas.height))

        let pad = p * min(canvas.width, canvas.height)
        let room = CGSize(width: canvas.width - 2 * pad, height: canvas.height - 2 * pad)
        let fit = min(room.width / recording.width, room.height / recording.height)
        let size = CGSize(width: recording.width * fit, height: recording.height * fit)
        let content = CGRect(
            x: ((canvas.width - size.width) / 2).rounded(), y: ((canvas.height - size.height) / 2).rounded(),
            width: size.width.rounded(), height: size.height.rounded()
        )
        return Framing(canvas: canvas, content: content, corner: windowCorner * scale * fit, background: background)
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        CGFloat(Int(value.rounded()) & ~1)
    }
}

/// Frames a rendered movie on a canvas (`Framing`): the movie's picture with rounded corners and a soft shadow over
/// the background, its sound kept. A video background loops under it, silent.
public enum Framer {
    public static func frame(_ movie: URL, with framing: Framing, frameRate: Int, to output: Output, lossless: Bool)
        async throws
    {
        let source = AVURLAsset(url: movie)
        let length = try await source.load(.duration)
        let whole = CMTimeRange(start: .zero, duration: length)
        guard let picture = try await source.loadTracks(withMediaType: .video).first else {
            throw ReelError("\(movie.path) has no picture")
        }
        let composition = AVMutableComposition()
        guard let pictureTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ReelError("cannot frame \(movie.path)") }
        try pictureTrack.insertTimeRange(whole, of: picture, at: .zero)
        for sound in try await source.loadTracks(withMediaType: .audio) {
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
                .insertTimeRange(whole, of: sound, at: .zero)
        }

        // A video background, looped to the movie's length.
        var backdropTrack: CMPersistentTrackID?
        var image: CIImage?
        var backdropAsset: AVURLAsset?
        switch framing.background {
        case let .video(url):
            guard FileManager.default.fileExists(atPath: url.path)
            else { throw ReelError("no background video at \(url.path)") }
            let asset = AVURLAsset(url: url)
            backdropAsset = asset
            guard let video = try await asset.loadTracks(withMediaType: .video).first,
                  let track = composition.addMutableTrack(
                      withMediaType: .video,
                      preferredTrackID: kCMPersistentTrackID_Invalid
                  )
            else { throw ReelError("\(url.path) has no picture") }
            let loop = try await video.load(.timeRange)
            guard loop.duration > .zero else { throw ReelError("\(url.path) is empty") }
            var at = CMTime.zero
            while at < length {
                let piece = CMTimeMinimum(loop.duration, length - at)
                try track.insertTimeRange(CMTimeRange(start: loop.start, duration: piece), of: video, at: at)
                at = CMTimeAdd(at, piece)
            }
            backdropTrack = track.trackID
        case let .image(url):
            guard let loaded = CIImage(contentsOf: url) else { throw ReelError("cannot read the image \(url.path)") }
            image = loaded
        case .color:
            break
        }

        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = FrameCompositor.self
        video.renderSize = framing.canvas
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        video.instructions = [FrameInstruction(
            timeRange: whole, picture: pictureTrack.trackID, backdrop: backdropTrack, framing: framing, image: image
        )]

        let preset = lossless ? AVAssetExportPresetAppleProRes422LPCM : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ReelError("cannot frame \(movie.path)")
        }
        session.videoComposition = video
        try FileManager.default.createDirectory(
            at: output.url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: output.url)
        try await session.export(to: output.url, as: output.format == .mp4 ? .mp4 : .mov)
        withExtendedLifetime(backdropAsset) {}
    }
}

/// What the compositor draws for the whole movie: which track is the picture, which (if any) the background.
final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let picture: CMPersistentTrackID
    let backdrop: CMPersistentTrackID?
    let framing: Framing
    let image: CIImage?

    init(
        timeRange: CMTimeRange, picture: CMPersistentTrackID, backdrop: CMPersistentTrackID?, framing: Framing,
        image: CIImage?
    ) {
        self.timeRange = timeRange
        self.picture = picture
        self.backdrop = backdrop
        self.framing = framing
        self.image = image
        requiredSourceTrackIDs = ([picture] + (backdrop.map { [$0] } ?? [])).map { NSNumber(value: $0) }
    }
}

/// Draws each framed frame with Core Image: the background (colour, image or video, filling the canvas), a soft
/// shadow, and the picture with rounded corners.
final class FrameCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
              let source = request.sourceFrame(byTrackID: instruction.picture),
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: ReelError("a frame could not be framed"))
            return
        }
        let backdrop = instruction.backdrop.flatMap { request.sourceFrame(byTrackID: $0) }
            .map { CIImage(cvPixelBuffer: $0) }
        let image = Self.compose(
            picture: CIImage(cvPixelBuffer: source), backdrop: backdrop ?? instruction.image,
            framing: instruction.framing
        )
        Self.context.render(
            image, to: output, bounds: CGRect(origin: .zero, size: instruction.framing.canvas),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        request.finish(withComposedVideoFrame: output)
    }

    /// One framed frame. Core Image's y runs up from the bottom; the framing's from the top.
    static func compose(picture: CIImage, backdrop: CIImage?, framing: Framing) -> CIImage {
        let canvas = CGRect(origin: .zero, size: framing.canvas)
        let background: CIImage = if let backdrop {
            fill(backdrop, into: canvas)
        } else if case let .color(r, g, b) = framing.background {
            CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: canvas)
        } else {
            CIImage(color: .black).cropped(to: canvas)
        }
        let slot = CGRect(
            x: framing.content.minX, y: framing.canvas.height - framing.content.maxY,
            width: framing.content.width, height: framing.content.height
        )
        let placed = picture
            .transformed(by: CGAffineTransform(
                scaleX: slot.width / picture.extent.width, y: slot.height / picture.extent.height
            ))
            .transformed(by: CGAffineTransform(translationX: slot.minX, y: slot.minY))
        let rounded = CIFilter.roundedRectangleGenerator()
        rounded.extent = slot
        rounded.radius = Float(framing.corner)
        rounded.color = .white
        let mask = rounded.outputImage ?? CIImage.empty()
        // The shadow: the window's shape, dark, blurred, a little below it.
        let blur = slot.width * 0.025
        let shadow = mask
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.45),
            ])
            .applyingGaussianBlur(sigma: blur)
            .transformed(by: CGAffineTransform(translationX: 0, y: -slot.height * 0.012))
            .cropped(to: canvas)
        let window = placed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
        ])
        return window.composited(over: shadow.composited(over: background)).cropped(to: canvas)
    }

    /// Scales an image to cover `rect`, centred, cropping what overflows.
    static func fill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let extent = image.extent
        let scale = max(rect.width / extent.width, rect.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGPoint(
            x: (rect.width - extent.width * scale) / 2, y: (rect.height - extent.height * scale) / 2
        )
        return scaled.transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y)).cropped(to: rect)
    }
}

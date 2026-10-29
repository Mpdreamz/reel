import AppKit
import AVFoundation
import QuartzCore

/// Turns a take into a tape's outputs: the take, with its overlays drawn over it by Core Animation, exported.
public enum Renderer {
    /// Renders every Output of `tape`. A GIF is made from a rendered movie: the first movie Output's, or a temporary
    /// one when the tape has none.
    public static func render(tape: Tape, from location: TakeLocation, log: (String) -> Void) async throws {
        let take = try location.read()
        var overlays = try OverlayPlan.make(tape: tape, take: take)
        // Only what the take was recorded with: voiced again, a line may come out a different length.
        let narration = try await Narration.prepare(
            tape, into: location.directory, with: tape.voice.synthesizer(), voicing: false, log: log
        )
        let soundtrack = try Soundtrack.make(tape: tape, take: take, narration: narration)
        if tape.voice.subtitles {
            overlays = OverlayPlan.adding(subtitles: soundtrack.clips, to: overlays)
        }
        var movie: URL?
        for output in tape.outputs where output.format != .gif {
            try await render(location.movie, take: take, overlays: overlays, soundtrack: soundtrack, to: output)
            movie = movie ?? output.url
            log("wrote \(output.url.path)")
        }
        let gifs = tape.outputs.filter { $0.format == .gif }
        guard !gifs.isEmpty else { return }
        let source = movie ?? location.directory.appending(path: "rendered.mov")
        if movie == nil {
            try await render(
                location.movie, take: take, overlays: overlays, soundtrack: .none, to: Output(url: source, format: .mov)
            )
        }
        for gif in gifs {
            let result = try await GifWriter.write(
                from: source, to: gif.url, frameRate: tape.gifFrameRate, width: tape.gifWidth
            )
            log("wrote \(gif.url.path) (\(result.frames) frames of \(result.sampled) sampled)")
        }
    }

    /// The take, its narration mixed in with the app's sound ducked under it, and its overlays drawn over it.
    public static func render(
        _ movie: URL, take: Take, overlays: [Overlay], soundtrack: Soundtrack, to output: Output
    ) async throws {
        precondition(output.format != .gif, "a GIF is written from a rendered movie by GifWriter")
        let source = AVURLAsset(url: movie)
        let length = try await source.load(.duration)
        let whole = CMTimeRange(start: .zero, duration: length)
        let composition = AVMutableComposition()
        var mix: [AVMutableAudioMixInputParameters] = []

        if let picture = try await source.loadTracks(withMediaType: .video).first,
           let track = composition.addMutableTrack(
               withMediaType: .video,
               preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            try track.insertTimeRange(whole, of: picture, at: .zero)
        }
        if let sound = try await source.loadTracks(withMediaType: .audio).first,
           let track = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            try track.insertTimeRange(whole, of: sound, at: .zero)
            let app = AVMutableAudioMixInputParameters(track: track)
            app.setVolume(Float(soundtrack.appVolume), at: .zero)
            for ramp in soundtrack.appRamps {
                app.setVolumeRamp(
                    fromStartVolume: Float(ramp.from), toEndVolume: Float(ramp.to),
                    timeRange: CMTimeRange(start: time(ramp.start), end: time(ramp.end))
                )
            }
            mix.append(app)
        }
        if !soundtrack.clips.isEmpty,
           let track = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            for clip in soundtrack.clips {
                var at = clip.start
                for (piece, length) in zip(clip.pieces, clip.lengths) {
                    defer { at += length }
                    guard let piece else { continue }
                    // Held until the insert: a track whose asset is already gone fails to insert.
                    let asset = AVURLAsset(url: piece)
                    guard let audio = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                    // Never past the end of the clip's own track, nor past the end of the picture.
                    let own = try await audio.load(.timeRange)
                    let fits = min(length, own.duration.seconds, whole.duration.seconds - at)
                    guard fits > 0 else { continue }
                    try track.insertTimeRange(
                        CMTimeRange(start: own.start, duration: time(fits)), of: audio, at: time(at)
                    )
                }
            }
            let voice = AVMutableAudioMixInputParameters(track: track)
            voice.setVolume(Float(soundtrack.voiceVolume), at: .zero)
            mix.append(voice)
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else {
            throw ReelError("cannot export \(movie.path)")
        }
        if !mix.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = mix
            session.audioMix = audioMix
        }
        if !overlays.isEmpty {
            let video = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
            // Capture is variable rate (a still window sends no frames); overlays animate at the tape's rate.
            video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(take.frameRate))
            let size = video.renderSize
            let picture = CALayer()
            picture.frame = CGRect(origin: .zero, size: size)
            let parent = CALayer()
            parent.frame = picture.frame
            parent.addSublayer(picture)
            for overlay in overlays {
                parent.addSublayer(OverlayLayers.layer(for: overlay, in: size, scale: take.scale))
            }
            video.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: picture, in: parent)
            session.videoComposition = video
        }
        try FileManager.default.createDirectory(
            at: output.url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: output.url)
        let type: AVFileType = switch output.format {
        case .mp4: .mp4
        case .mov: .mov
        case .gif: preconditionFailure()
        }
        try await session.export(to: output.url, as: type)
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48000)
    }
}

/// The look of each overlay, sized from the video so a caption reads the same at any resolution. Core Animation's
/// origin is the bottom left here; the timeline's points are from the window's top left.
enum OverlayLayers {
    static let fade = 0.15

    static func layer(for overlay: Overlay, in size: CGSize, scale: Double) -> CALayer {
        let layer: CALayer
        var fades = true
        switch overlay.kind {
        case let .caption(text):
            layer = pill(text, fontSize: max(18, size.height * 0.045), weight: .semibold, in: size)
            layer.position = CGPoint(x: size.width / 2, y: size.height * 0.06 + layer.bounds.height / 2)
        case let .keys(text):
            layer = pill(text, fontSize: max(20, size.height * 0.055), weight: .medium, in: size)
            layer.position = CGPoint(x: size.width / 2, y: size.height * 0.2 + layer.bounds.height / 2)
        case let .ripple(point):
            layer = ripple(radius: 22 * scale, line: 2 * scale)
            layer.position = CGPoint(x: point.x * scale, y: size.height - point.y * scale)
            fades = false
        }
        layer.opacity = 0
        let duration = overlay.end - overlay.start
        let animation: CAAnimation
        if fades {
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            let edge = min(fade, duration / 3) / duration
            opacity.values = [0, 1, 1, 0]
            opacity.keyTimes = [0, edge, 1 - edge, 1].map { NSNumber(value: $0) }
            animation = opacity
        } else {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.3
            grow.toValue = 1.4
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.9
            opacity.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [grow, opacity]
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animation = group
        }
        // AVFoundation reads a begin time of 0 as "now"; its own zero is the start of the movie.
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + overlay.start
        animation.duration = duration
        // Forwards only: holding the first values backwards would show a ripple (opacity 0.9 at its start) from the
        // beginning of the movie. Before its start the layer's own opacity, 0, applies.
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "show")
        return layer
    }

    /// White text on a dark rounded pill, wrapped to most of the video's width. Drawn into an image rather than
    /// with a `CATextLayer`, which draws no text when AVFoundation renders the layers off screen.
    static func pill(_ text: String, fontSize: CGFloat, weight: NSFont.Weight, in size: CGSize) -> CALayer {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ])
        let padX = fontSize * 0.8, padY = fontSize * 0.45
        let fits = string.boundingRect(
            with: CGSize(width: size.width * 0.86 - 2 * padX, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textSize = CGSize(width: ceil(fits.width), height: ceil(fits.height))
        let bounds = CGRect(x: 0, y: 0, width: textSize.width + 2 * padX, height: textSize.height + 2 * padY)

        let layer = CALayer()
        layer.bounds = bounds
        guard let context = CGContext(
            data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return layer }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let radius = min(bounds.height / 2, fontSize)
        NSColor(white: 0, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        string.draw(
            with: CGRect(origin: CGPoint(x: padX, y: padY), size: textSize),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        NSGraphicsContext.restoreGraphicsState()
        layer.contents = context.makeImage()
        return layer
    }

    static func ripple(radius: CGFloat, line: CGFloat) -> CALayer {
        let circle = CAShapeLayer()
        circle.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        circle.path = CGPath(ellipseIn: circle.bounds.insetBy(dx: line, dy: line), transform: nil)
        circle.fillColor = NSColor(white: 1, alpha: 0.35).cgColor
        circle.strokeColor = NSColor(white: 1, alpha: 0.9).cgColor
        circle.lineWidth = line
        return circle
    }
}

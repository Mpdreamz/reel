import AppKit
import AVFoundation
import QuartzCore

/// Turns a take into a tape's outputs: the take, cut and sped up as the tape says, zoomed, its narration mixed in, its
/// overlays drawn over it by Core Animation, exported.
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
        let edit = try Edit.make(tape: tape, take: take, spoken: soundtrack.clips.map { $0.start ... $0.end })
        let zoom = ZoomPlan.make(tape: tape, take: take)
        zoom.notes.forEach(log)
        let cut = Cut(edit: edit, zoom: zoom)
        // How the take's time became the output's, next to the take: for anyone matching the two up.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(edit).write(to: location.directory.appending(path: "edit.json"))
        var movie: URL?
        // With an intro or an outro, the demo is rendered once, losslessly, and each output assembled from it.
        let sectioned = tape.intro != nil || tape.outro != nil
        let demo = location.directory.appending(path: "demo.mov")
        if sectioned {
            try await render(
                location.movie, take: take, overlays: overlays, soundtrack: soundtrack, cut: cut,
                to: Output(url: demo, format: .mov), lossless: true
            )
        }
        for output in tape.outputs where output.format != .gif {
            if sectioned {
                let arrangement = try await Assembler.assemble(
                    main: demo, intro: tape.intro, outro: tape.outro, frameRate: take.frameRate,
                    in: location.directory, to: output
                )
                // Where the demo sits in the finished movie, next to the take, for anyone matching the two up.
                try JSONSerialization.data(
                    withJSONObject: ["demoStart": arrangement.main.start, "duration": arrangement.duration],
                    options: [.prettyPrinted, .sortedKeys]
                ).write(to: location.directory.appending(path: "sections.json"))
            } else {
                try await render(
                    location.movie, take: take, overlays: overlays, soundtrack: soundtrack, cut: cut, to: output
                )
            }
            movie = movie ?? output.url
            log("wrote \(output.url.path)")
        }
        let gifs = tape.outputs.filter { $0.format == .gif }
        guard !gifs.isEmpty else { return }
        let source = movie ?? location.directory.appending(path: "rendered.mov")
        if movie == nil {
            if sectioned {
                try await Assembler.assemble(
                    main: demo, intro: tape.intro, outro: tape.outro, frameRate: take.frameRate,
                    in: location.directory, to: Output(url: source, format: .mov)
                )
            } else {
                try await render(
                    location.movie, take: take, overlays: overlays, soundtrack: .none, cut: cut,
                    to: Output(url: source, format: .mov)
                )
            }
        }
        for gif in gifs {
            let result = try await GifWriter.write(
                from: source, to: gif.url, frameRate: tape.gifFrameRate, width: tape.gifWidth
            )
            log("wrote \(gif.url.path) (\(result.frames) frames of \(result.sampled) sampled)")
        }
    }

    /// How the take is edited: its time (`Hide`, `Speed`) and what part of the window shows (`Zoom`).
    public struct Cut: Sendable {
        public var edit: Edit?
        public var zoom: ZoomPlan?

        public init(edit: Edit? = nil, zoom: ZoomPlan? = nil) {
            self.edit = edit
            self.zoom = zoom
        }
    }

    /// The take, with times in `overlays` and `soundtrack` those of the take: they are mapped through the cut here.
    public static func render(
        _ movie: URL, take: Take, overlays: [Overlay], soundtrack: Soundtrack, cut: Cut = Cut(), to output: Output,
        lossless: Bool = false
    ) async throws {
        precondition(output.format != .gif, "a GIF is written from a rendered movie by GifWriter")
        let source = AVURLAsset(url: movie)
        let length = try await source.load(.duration)
        let edit = cut.edit ?? .whole(length.seconds)
        let composition = AVMutableComposition()
        var mix: [AVMutableAudioMixInputParameters] = []

        // The kept stretches, one after another; a sped-up one is scaled where it lands and carries no app sound,
        // which sped up is only noise.
        let picture = try await source.loadTracks(withMediaType: .video).first
        let sound = try await source.loadTracks(withMediaType: .audio).first
        let videoTrack = picture.flatMap { _ in
            composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        let appTrack = sound.flatMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        var at = CMTime.zero
        for segment in edit.segments {
            let range = CMTimeRange(start: time(segment.start), end: CMTimeMinimum(time(segment.end), length))
            guard range.duration > .zero else { continue }
            if let picture { try videoTrack?.insertTimeRange(range, of: picture, at: at) }
            if let sound {
                if segment.rate == 1 {
                    try appTrack?.insertTimeRange(range, of: sound, at: at)
                } else {
                    appTrack?.insertEmptyTimeRange(CMTimeRange(start: at, duration: range.duration))
                }
            }
            var landed = range.duration
            if segment.rate != 1 {
                landed = time(range.duration.seconds / segment.rate)
                composition.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: landed)
            }
            at = CMTimeAdd(at, landed)
        }
        let whole = CMTimeRange(start: .zero, duration: at)
        let placed = soundtrack.mapped(through: edit)

        if let appTrack {
            let app = AVMutableAudioMixInputParameters(track: appTrack)
            app.setVolume(Float(placed.appVolume), at: .zero)
            for ramp in placed.appRamps {
                app.setVolumeRamp(
                    fromStartVolume: Float(ramp.from), toEndVolume: Float(ramp.to),
                    timeRange: CMTimeRange(start: time(ramp.start), end: time(ramp.end))
                )
            }
            mix.append(app)
        }
        if !placed.clips.isEmpty,
           let track = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           )
        {
            for clip in placed.clips {
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
            voice.setVolume(Float(placed.voiceVolume), at: .zero)
            mix.append(voice)
        }

        // Lossless (ProRes and PCM) for a demo that is assembled again, so the second encode is the only one.
        let preset = lossless ? AVAssetExportPresetAppleProRes422LPCM : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ReelError("cannot export \(movie.path)")
        }
        if !mix.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = mix
            session.audioMix = audioMix
        }
        let zoomed = cut.zoom.map { !$0.states.isEmpty } ?? false
        if let videoTrack, let picture, !overlays.isEmpty || zoomed {
            let size = try await picture.load(.naturalSize)
            let video = AVMutableVideoComposition()
            video.renderSize = size
            // Capture is variable rate (a still window sends no frames); overlays and zooms move at the tape's rate.
            video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(take.frameRate))
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = whole
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            if let zoom = cut.zoom, zoomed { apply(zoom, to: layer, edit: edit, scale: take.scale) }
            instruction.layerInstructions = [layer]
            video.instructions = [instruction]
            if !overlays.isEmpty {
                let picture = CALayer()
                picture.frame = CGRect(origin: .zero, size: size)
                let parent = CALayer()
                parent.frame = picture.frame
                parent.addSublayer(picture)
                for overlay in OverlayPlan.mapped(overlays, through: edit, zoom: cut.zoom) {
                    parent.addSublayer(OverlayLayers.layer(for: overlay, in: size, scale: take.scale))
                }
                video.animationTool = AVVideoCompositionCoreAnimationTool(
                    postProcessingAsVideoLayer: picture, in: parent
                )
            }
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

    /// The zoom as transform ramps, sampled 30 times a second of the take and placed in the output's time.
    static func apply(
        _ zoom: ZoomPlan,
        to layer: AVMutableVideoCompositionLayerInstruction,
        edit: Edit,
        scale: Double
    ) {
        func transform(_ region: CGRect) -> CGAffineTransform {
            let zoomed = zoom.window.width / region.width
            return CGAffineTransform(
                a: zoomed, b: 0, c: 0, d: zoomed, tx: -zoomed * region.minX * scale, ty: -zoomed * region.minY * scale
            )
        }
        var last: (out: Double, region: CGRect)?
        layer.setTransform(transform(zoom.region(at: 0)), at: .zero)
        for segment in edit.segments {
            let step = segment.rate / 30
            var source = segment.start
            while source <= segment.end {
                let region = zoom.region(at: source)
                let out = edit.map(source)
                if let previous = last, out > previous.out, region != previous.region {
                    layer.setTransformRamp(
                        fromStart: transform(previous.region), toEnd: transform(region),
                        timeRange: CMTimeRange(start: time(previous.out), end: time(out))
                    )
                }
                last = (out, region)
                source += step
            }
        }
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

    /// White centred text with a soft shadow, wrapped to `width`, as an image: a section's title or subtitle.
    static func text(_ text: String, fontSize: CGFloat, weight: NSFont.Weight, width: CGFloat) -> CALayer {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.6)
        shadow.shadowBlurRadius = fontSize * 0.15
        shadow.shadowOffset = NSSize(width: 0, height: -fontSize * 0.04)
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
            .shadow: shadow,
        ])
        let fits = string.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let pad = fontSize * 0.3
        let bounds = CGRect(x: 0, y: 0, width: ceil(fits.width) + 2 * pad, height: ceil(fits.height) + 2 * pad)
        let layer = CALayer()
        layer.bounds = bounds
        guard let context = CGContext(
            data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return layer }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(
            with: CGRect(x: pad, y: pad, width: ceil(fits.width), height: ceil(fits.height)),
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

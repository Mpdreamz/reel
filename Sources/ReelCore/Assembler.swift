import AppKit
import AVFoundation
import QuartzCore

/// Where the intro, the demo and the outro sit in the finished movie, and the windows their transitions play in.
public struct Arrangement: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var transition: SectionTransition

        func progress(_ time: Double) -> Double? {
            guard time >= start, time <= end else { return nil }
            return end > start ? transition.easing((time - start) / (end - start)) : 1
        }
    }

    /// Each part's start and length in seconds; nil when the tape has no such section.
    public var intro: (start: Double, length: Double)?
    public var main: (start: Double, length: Double)
    public var outro: (start: Double, length: Double)?
    /// The intro moving into the demo, and the demo moving into the outro.
    public var into: Window?
    public var outOf: Window?

    public var duration: Double {
        outro.map { $0.start + $0.length } ?? main.start + main.length
    }

    /// A section's transition overlaps the two parts for its length (crossfades, slides, zooms, wipes); a fade goes
    /// through black across the cut instead, half on either side; a cut has none.
    public init(
        intro: Double?,
        introTransition: SectionTransition?,
        main: Double,
        outro: Double?,
        outroTransition: SectionTransition?
    ) throws {
        var at = 0.0
        if let intro, let transition = introTransition {
            let length = transition.seconds
            guard intro >= length else {
                throw ReelError(String(
                    format: "the Intro is shorter (%.2f s) than its transition (%.2f s)",
                    intro,
                    length
                ))
            }
            self.intro = (0, intro)
            let overlap = transition.kind.overlaps ? length : 0
            let half = transition.kind == .fade ? length / 2 : 0
            into = Window(start: intro - overlap - half, end: intro + half, transition: transition)
            at = intro - overlap
        }
        self.main = (at, main)
        at += main
        if let outro, let transition = outroTransition {
            let length = transition.seconds
            guard outro >= length, main >= length else {
                throw ReelError(String(
                    format: "the Outro (%.2f s) or the demo is shorter than its transition (%.2f s)",
                    outro,
                    length
                ))
            }
            let overlap = transition.kind.overlaps ? length : 0
            let half = transition.kind == .fade ? length / 2 : 0
            self.outro = (at - overlap, outro)
            outOf = Window(start: at - overlap - half, end: at - overlap + half + overlap, transition: transition)
        }
    }

    public enum Part: Sendable {
        case intro, main, outro
    }

    /// How a part looks at `time`. The intro is drawn on top of the demo, the outro too.
    public func look(_ part: Part, at time: Double) -> Look {
        switch part {
        case .intro:
            if let into, let p = into.progress(time) {
                return .of(into.transition.kind, progress: p, outgoing: true, onTop: true)
            }
        case .main:
            if let into, let p = into.progress(time) {
                return .of(into.transition.kind, progress: p, outgoing: false, onTop: false)
            }
            if let outOf, let p = outOf.progress(time) {
                return .of(outOf.transition.kind, progress: p, outgoing: true, onTop: false)
            }
        case .outro:
            if let outOf, let p = outOf.progress(time) {
                return .of(outOf.transition.kind, progress: p, outgoing: false, onTop: true)
            }
        }
        return .still
    }

    /// A part's sound at `time`: the one going out fades as the one coming in rises (through silence for a fade).
    public func volume(_ part: Part, at time: Double) -> Double {
        func level(_ window: Window, outgoing: Bool) -> Double? {
            guard let p = window.progress(time) else { return nil }
            switch window.transition.kind {
            case .cut: return outgoing ? (p < 1 ? 1 : 0) : (p > 0 ? 1 : 0)
            case .fade: return outgoing ? max(0, 1 - 2 * p) : max(0, 2 * p - 1)
            default: return outgoing ? 1 - p : p
            }
        }
        switch part {
        case .intro: return into.flatMap { level($0, outgoing: true) } ?? 1
        case .main:
            return into.flatMap { level($0, outgoing: false) } ?? outOf.flatMap { level($0, outgoing: true) } ?? 1
        case .outro: return outOf.flatMap { level($0, outgoing: false) } ?? 1
        }
    }

    public static func == (a: Arrangement, b: Arrangement) -> Bool {
        a.intro?.start == b.intro?.start && a.intro?.length == b.intro?.length && a.main == b.main
            && a.outro?.start == b.outro?.start && a.outro?.length == b.outro?.length && a.into == b.into
            && a.outOf == b.outOf
    }
}

/// Puts the intro, the rendered demo and the outro together, with their transitions and titles.
public enum Assembler {
    static let samplesPerSecond = 30.0
    /// How long a title takes to appear once its section shows.
    static let titleFadeIn = 0.4

    @discardableResult
    public static func assemble(
        main: URL, intro: Section?, outro: Section?, frameRate: Int, in directory: URL, to output: Output
    ) async throws -> Arrangement {
        precondition(output.format != .gif, "a GIF is written from a rendered movie by GifWriter")
        let demo = AVURLAsset(url: main)
        guard let demoPicture = try await demo.loadTracks(withMediaType: .video).first else {
            throw ReelError("\(main.path) has no picture")
        }
        let size = try await demoPicture.load(.naturalSize)
        let demoLength = try await demo.load(.duration).seconds

        // Each section's clip: its video, or a still of its colour or image as long as the section.
        func clip(_ section: Section, name: String) async throws -> (asset: AVURLAsset, length: Double) {
            switch section.background {
            case let .video(url):
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ReelError("no background video at \(url.path)")
                }
                let asset = AVURLAsset(url: url)
                let own = try await asset.load(.duration).seconds
                return (asset, section.duration.map { min($0.seconds, own) } ?? own)
            default:
                let length = (section.duration ?? Section.defaultLength).seconds
                let url = directory.appending(path: "\(name).mov")
                try await StillClip.write(section.background, size: size, seconds: length, to: url)
                return (AVURLAsset(url: url), length)
            }
        }
        var introClip: (asset: AVURLAsset, length: Double)?, outroClip: (asset: AVURLAsset, length: Double)?
        if let intro { introClip = try await clip(intro, name: "intro") }
        if let outro { outroClip = try await clip(outro, name: "outro") }
        let arrangement = try Arrangement(
            intro: introClip?.length, introTransition: intro?.transition, main: demoLength,
            outro: outroClip?.length, outroTransition: outro?.transition
        )

        let composition = AVMutableComposition()
        var layers: [AVMutableVideoCompositionLayerInstruction] = []
        var mix: [AVMutableAudioMixInputParameters] = []
        // Drawn top to bottom: the intro, the outro, then the demo.
        var parts: [(Arrangement.Part, AVURLAsset, Double, Double)] = []
        if let introClip, let at = arrangement.intro { parts.append((
            .intro,
            introClip.asset,
            at.start,
            introClip.length
        )) }
        if let outroClip, let at = arrangement.outro { parts.append((
            .outro,
            outroClip.asset,
            at.start,
            outroClip.length
        )) }
        parts.append((.main, demo, arrangement.main.start, demoLength))
        for (part, asset, start, length) in parts {
            let range = CMTimeRange(start: .zero, duration: time(length))
            if let picture = try await asset.loadTracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(
                   withMediaType: .video,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               )
            {
                let own = try await picture.load(.timeRange)
                try track.insertTimeRange(
                    CMTimeRange(start: own.start, duration: CMTimeMinimum(range.duration, own.duration)), of: picture,
                    at: time(start)
                )
                let natural = try await picture.load(.naturalSize)
                let oriented = try await picture.load(.preferredTransform)
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                apply(
                    arrangement,
                    part: part,
                    to: layer,
                    base: fill(natural, oriented: oriented, into: size),
                    natural: natural,
                    size: size,
                    from: start,
                    to: start + length
                )
                layers.append(layer)
            }
            for sound in try await asset.loadTracks(withMediaType: .audio) {
                guard let track = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { continue }
                let own = try await sound.load(.timeRange)
                try track.insertTimeRange(
                    CMTimeRange(start: own.start, duration: CMTimeMinimum(range.duration, own.duration)), of: sound,
                    at: time(start)
                )
                let levels = AVMutableAudioMixInputParameters(track: track)
                rampVolume(arrangement, part: part, on: levels, from: start, to: start + length)
                mix.append(levels)
            }
        }

        let video = AVMutableVideoComposition()
        video.renderSize = size
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: time(arrangement.duration))
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        instruction.layerInstructions = layers
        video.instructions = [instruction]

        // The titles, over everything, moving with their sections.
        let picture = CALayer()
        picture.frame = CGRect(origin: .zero, size: size)
        let parent = CALayer()
        parent.frame = picture.frame
        parent.addSublayer(picture)
        if let intro, let at = arrangement.intro {
            parent.addSublayer(titles(
                intro,
                part: .intro,
                arrangement: arrangement,
                size: size,
                from: at.start,
                to: at.start + at.length
            ))
        }
        if let outro, let at = arrangement.outro {
            parent.addSublayer(titles(
                outro,
                part: .outro,
                arrangement: arrangement,
                size: size,
                from: at.start,
                to: at.start + at.length
            ))
        }
        video.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: picture, in: parent)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw ReelError("cannot assemble \(output.url.path)") }
        session.videoComposition = video
        if !mix.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = mix
            session.audioMix = audioMix
        }
        try FileManager.default.createDirectory(
            at: output.url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: output.url)
        try await session.export(to: output.url, as: output.format == .mp4 ? .mp4 : .mov)
        return arrangement
    }

    /// Scales a track to fill the frame, cropping what overflows, centred.
    static func fill(_ natural: CGSize, oriented: CGAffineTransform, into size: CGSize) -> CGAffineTransform {
        let upright = CGRect(origin: .zero, size: natural).applying(oriented)
        let scale = max(size.width / abs(upright.width), size.height / abs(upright.height))
        let shown = CGSize(width: abs(upright.width) * scale, height: abs(upright.height) * scale)
        return oriented
            .concatenating(CGAffineTransform(translationX: -upright.minX, y: -upright.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: (size.width - shown.width) / 2, y: (size.height - shown.height) / 2
            ))
    }

    /// The part's look through its transitions, sampled into ramps on its layer.
    static func apply(
        _ arrangement: Arrangement, part: Arrangement.Part, to layer: AVMutableVideoCompositionLayerInstruction,
        base: CGAffineTransform, natural: CGSize, size: CGSize, from start: Double, to end: Double
    ) {
        func transform(_ look: Look) -> CGAffineTransform {
            base
                .concatenating(CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2))
                .concatenating(CGAffineTransform(scaleX: look.scale, y: look.scale))
                .concatenating(CGAffineTransform(
                    translationX: size.width / 2 + look.offset.x * size.width,
                    y: size.height / 2 + look.offset.y * size.height
                ))
        }
        func crop(_ look: Look) -> CGRect {
            let shown = CGRect(
                x: look.crop.minX * size.width, y: look.crop.minY * size.height,
                width: look.crop.width * size.width, height: look.crop.height * size.height
            )
            return shown.applying(base.inverted()).intersection(CGRect(origin: .zero, size: natural))
        }
        var last = arrangement.look(part, at: start)
        layer.setOpacity(Float(last.opacity), at: time(start))
        layer.setTransform(transform(last), at: time(start))
        layer.setCropRectangle(crop(last), at: time(start))
        var at = start
        for t in samples(from: start, to: end) {
            let look = arrangement.look(part, at: t)
            if look != last {
                let range = CMTimeRange(start: time(at), end: time(t))
                if look.opacity != last.opacity {
                    layer.setOpacityRamp(
                        fromStartOpacity: Float(last.opacity),
                        toEndOpacity: Float(look.opacity),
                        timeRange: range
                    )
                }
                if look.offset != last.offset || look.scale != last.scale {
                    layer.setTransformRamp(fromStart: transform(last), toEnd: transform(look), timeRange: range)
                }
                if look.crop != last.crop {
                    layer.setCropRectangleRamp(
                        fromStartCropRectangle: crop(last),
                        toEndCropRectangle: crop(look),
                        timeRange: range
                    )
                }
            }
            last = look
            at = t
        }
    }

    static func rampVolume(
        _ arrangement: Arrangement, part: Arrangement.Part, on levels: AVMutableAudioMixInputParameters,
        from start: Double, to end: Double
    ) {
        var last = arrangement.volume(part, at: start), at = start
        levels.setVolume(Float(last), at: time(start))
        for t in samples(from: start, to: end) {
            let volume = arrangement.volume(part, at: t)
            if volume != last {
                levels.setVolumeRamp(
                    fromStartVolume: Float(last),
                    toEndVolume: Float(volume),
                    timeRange: CMTimeRange(start: time(at), end: time(t))
                )
            }
            last = volume
            at = t
        }
    }

    /// A section's title and subtitle, centred, appearing as it shows and moving with it.
    static func titles(
        _ section: Section, part: Arrangement.Part, arrangement: Arrangement, size: CGSize, from start: Double,
        to end: Double
    ) -> CALayer {
        let group = CALayer()
        group.frame = CGRect(origin: .zero, size: size)
        group.opacity = 0
        let title = OverlayLayers.text(
            section.title, fontSize: max(28, size.height * 0.085), weight: .bold, width: size.width * 0.85
        )
        var height = title.bounds.height
        var subtitle: CALayer?
        if let text = section.subtitle {
            let layer = OverlayLayers.text(
                text, fontSize: max(16, size.height * 0.04), weight: .regular, width: size.width * 0.8
            )
            height += layer.bounds.height * 1.3
            subtitle = layer
        }
        // Centred as a block; Core Animation's y runs up.
        let top = (size.height + height) / 2
        title.position = CGPoint(x: size.width / 2, y: top - title.bounds.height / 2)
        group.addSublayer(title)
        if let subtitle {
            subtitle.position = CGPoint(x: size.width / 2, y: top - height + subtitle.bounds.height / 2)
            group.addSublayer(subtitle)
        }
        let mask = CALayer()
        mask.backgroundColor = CGColor(gray: 1, alpha: 1)
        mask.frame = group.bounds
        group.mask = mask

        let times = [start] + samples(from: start, to: end)
        let looks = times.map { arrangement.look(part, at: $0) }
        let keyTimes = times.map { NSNumber(value: end > start ? ($0 - start) / (end - start) : 0) }
        func animate(_ path: String, on layer: CALayer, _ values: [Any]) {
            let animation = CAKeyframeAnimation(keyPath: path)
            animation.values = values
            animation.keyTimes = keyTimes
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
            animation.duration = end - start
            animation.calculationMode = .linear
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: path)
        }
        animate("opacity", on: group, zip(times, looks).map { time, look in
            look.opacity * min(1, (time - start) / titleFadeIn)
        })
        animate("transform", on: group, looks.map { look in
            var transform = CATransform3DMakeTranslation(look.offset.x * size.width, -look.offset.y * size.height, 0)
            transform = CATransform3DScale(transform, look.scale, look.scale, 1)
            return NSValue(caTransform3D: transform)
        })
        animate("bounds", on: mask, looks.map { look in
            NSValue(rect: CGRect(
                x: 0,
                y: 0,
                width: look.crop.width * size.width,
                height: look.crop.height * size.height
            ))
        })
        animate("position", on: mask, looks.map { look in
            // The crop's centre, with y turned up.
            NSValue(point: CGPoint(x: look.crop.midX * size.width, y: (1 - look.crop.midY) * size.height))
        })
        return group
    }

    /// Times every `1 / samplesPerSecond` after `start`, up to and including `end`.
    static func samples(from start: Double, to end: Double) -> [Double] {
        let count = Int(((end - start) * samplesPerSecond).rounded(.up))
        return (1 ... max(1, count)).map { min(end, start + Double($0) / samplesPerSecond) }
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 48000)
    }
}

/// A short movie of one still frame: a colour or an image filling the frame, held for `seconds`.
enum StillClip {
    static func write(_ background: Background, size: CGSize, seconds: Double, to url: URL) async throws {
        let width = Int(size.width), height = Int(size.height)
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels
        )
        guard let buffer = pixels else { throw ReelError("cannot make a frame of \(width)×\(height)") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        let frame = CGRect(origin: .zero, size: size)
        switch background {
        case let .color(r, g, b):
            context?.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
            context?.fill(frame)
        case let .image(url):
            guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                CVPixelBufferUnlockBaseAddress(buffer, [])
                throw ReelError("cannot read the image \(url.path)")
            }
            // Filling the frame, cropped evenly.
            let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
            let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context?.draw(image, in: CGRect(
                x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width,
                height: drawn.height
            ))
        case .video:
            break
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: .zero, decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: format!, sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        guard let sample else { throw ReelError("cannot make a frame of \(width)×\(height)") }
        let writer = try TakeWriter(
            url: url,
            width: width,
            height: height,
            frameRate: 30,
            audio: false,
            realTime: false
        )
        nonisolated(unsafe) let still = sample
        await writer.perform { writer.append(video: still) }
        try await writer.finish(at: CMTime(seconds: seconds, preferredTimescale: 600))
    }
}

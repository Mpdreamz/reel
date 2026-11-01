import AVFoundation
import CoreImage

/// Where each track sits on the canvas: side by side when the canvas is wide, stacked when it is tall, each cell as
/// big as its track needs at the shared height (or width), with room between them.
struct TrackLayout: Equatable {
    var canvas: CGSize
    /// Pixels from the canvas's top left, in the tracks' order.
    var cells: [CGRect]
    var corners: [Double]

    /// `sizes` are the tracks' recordings in pixels, `scales` their pixels a point.
    static func make(sizes: [CGSize], scales: [Double], shape: Output.Shape, padding: Double) -> TrackLayout {
        let wide = switch shape {
        case let .aspect(w, h): w >= h
        case let .size(w, h): w >= h
        }
        // Each track at the tallest one's height (side by side) or the widest one's width (stacked).
        let side = wide ? sizes.map(\.height).max() ?? 1 : sizes.map(\.width).max() ?? 1
        let scaled = sizes.map { size in
            wide ? CGSize(width: size.width * side / size.height, height: side)
                : CGSize(width: side, height: size.height * side / size.width)
        }
        let gap = side * 0.04
        let gaps = gap * Double(max(0, sizes.count - 1))
        let content = wide
            ? CGSize(width: scaled.map(\.width).reduce(0, +) + gaps, height: side)
            : CGSize(width: side, height: scaled.map(\.height).reduce(0, +) + gaps)
        // Framed as one recording of that size would be: the same padding, shape and largest size.
        let framing = Framing.make(
            recording: content, scale: 1, shape: shape, padding: padding, background: .standard
        )
        let fit = framing.content.width / content.width
        var cells: [CGRect] = []
        var at = wide ? framing.content.minX : framing.content.minY
        for size in scaled {
            let cell = wide
                ? CGRect(x: at, y: framing.content.minY, width: size.width * fit, height: framing.content.height)
                : CGRect(x: framing.content.minX, y: at, width: framing.content.width, height: size.height * fit)
            cells.append(cell.integral)
            at += (wide ? cell.width : cell.height) + gap * fit
        }
        let corners = zip(sizes, zip(cells, scales)).map { size, cell in
            Framing.windowCorner * cell.1 * cell.0.width / size.width
        }
        return TrackLayout(canvas: framing.canvas, cells: cells, corners: corners)
    }
}

/// What the compositor draws for the whole movie: each track's picture in its cell, over the background.
final class TracksInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let pictures: [CMPersistentTrackID]
    let layout: TrackLayout
    let background: Background
    let image: CIImage?

    init(
        timeRange: CMTimeRange, pictures: [CMPersistentTrackID], layout: TrackLayout, background: Background,
        image: CIImage?
    ) {
        self.timeRange = timeRange
        self.pictures = pictures
        self.layout = layout
        self.background = background
        self.image = image
        requiredSourceTrackIDs = pictures.map { NSNumber(value: $0) }
    }
}

/// Draws every track's frame as a window in its cell. A track that has not started yet is not drawn; one that has
/// ended holds its last frame.
final class TracksCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private let lock = NSLock()
    private var last: [CMPersistentTrackID: CIImage] = [:]

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    func renderContextChanged(_: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? TracksInstruction,
              let output = request.renderContext.newPixelBuffer()
        else {
            request.finish(with: ReelError("the tracks could not be drawn"))
            return
        }
        let layout = instruction.layout
        let canvas = CGRect(origin: .zero, size: layout.canvas)
        var image: CIImage = if let backdrop = instruction.image {
            FrameCompositor.fill(backdrop, into: canvas)
        } else if case let .color(r, g, b) = instruction.background {
            CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: canvas)
        } else {
            CIImage(color: .black).cropped(to: canvas)
        }
        for (index, track) in instruction.pictures.enumerated() {
            let picture: CIImage? = lock.withLock {
                if let frame = request.sourceFrame(byTrackID: track) {
                    last[track] = CIImage(cvPixelBuffer: frame)
                }
                return last[track]
            }
            guard let picture else { continue }
            let cell = layout.cells[index]
            // Core Image's y runs up from the bottom; the layout's from the top.
            let slot = CGRect(x: cell.minX, y: layout.canvas.height - cell.maxY, width: cell.width, height: cell.height)
            image = FrameCompositor.window(picture, in: slot, corner: layout.corners[index], canvas: canvas)
                .composited(over: image)
        }
        Self.context.render(image, to: output, bounds: canvas, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        request.finish(withComposedVideoFrame: output)
    }
}

extension Renderer {
    /// A reel of tracks: each track rendered as its own reel renders it (its overlays, its cuts), then all of them
    /// drawn together on one canvas for each shape its Outputs take, lined up by when each started. That movie is
    /// then the director's take: narration, captions, the intro and outro go on it as on any take.
    static func renderTracks(tape: Tape, from location: TakeLocation, log: (String) -> Void) async throws {
        let directorURL = Tracks.director(in: location)
        guard let data = try? Data(contentsOf: directorURL),
              let director = try? JSONDecoder().decode(Take.self, from: data)
        else {
            throw ReelError("this reel has no take yet: record it (reel record), or record and render with reel run")
        }
        // Each track's demo, losslessly, and where it starts on the director's clock.
        var demos: [(url: URL, take: Take, offset: Int)] = []
        defer { demos.forEach { try? FileManager.default.removeItem(at: $0.url) } }
        for track in tape.tracks {
            let own = Tracks.location(of: track, in: location)
            let prepared: Prepared
            do {
                prepared = try await prepare(tape: track.tape, from: own, log: log)
            } catch {
                throw ReelError("\(track.name): \(error.localizedDescription)")
            }
            let url = location.directory.appending(path: "track-\(track.name).mov")
            try await render(
                own.movie, take: prepared.take, overlays: prepared.overlays, soundtrack: prepared.soundtrack,
                cut: prepared.cut, to: Output(url: url, format: .mov), lossless: true
            )
            let offset = max(0, (prepared.take.startedAt ?? 0) - (director.startedAt ?? 0))
            demos.append((url, prepared.take, offset))
        }
        let frameRate = demos.map(\.take.frameRate).max() ?? tape.frameRate

        // One composed take for each shape the Outputs take, each then rendered as any take is.
        let shapes = Dictionary(grouping: tape.outputs) { $0.shape ?? .aspect(16, 9) }
        for (shape, outputs) in shapes.sorted(by: { $0.key.description < $1.key.description }) {
            let cut = TakeLocation(directory: location.directory.appending(
                path: "cuts/\(shape.description.replacingOccurrences(of: ":", with: "x"))", directoryHint: .isDirectory
            ))
            try FileManager.default.createDirectory(at: cut.directory, withIntermediateDirectories: true)
            // The narration was voiced into the reel's own folder.
            let voices = cut.directory.appending(path: "voice")
            if !FileManager.default.fileExists(atPath: voices.path) {
                try? FileManager.default.createSymbolicLink(
                    at: voices, withDestinationURL: location.directory.appending(path: "voice")
                )
            }
            let layout = TrackLayout.make(
                sizes: demos.map { CGSize(width: $0.take.width, height: $0.take.height) },
                scales: demos.map(\.take.scale), shape: shape, padding: tape.padding
            )
            let length = try await compose(
                demos.map { ($0.url, $0.offset) }, layout: layout, background: tape.background ?? .standard,
                frameRate: frameRate, atLeast: director.durationMs, to: cut.movie
            )
            var take = Take(
                width: Int(layout.canvas.width), height: Int(layout.canvas.height),
                scale: demos.map(\.take.scale).max() ?? 2, frameRate: frameRate,
                audio: demos.contains(where: \.take.audio), durationMs: max(director.durationMs, length),
                events: director.events
            )
            take.startedAt = director.startedAt
            try cut.write(take)
            // The director's reel, its tracks already drawn: its Outputs of this shape, bare, on the canvas above.
            var reel = tape
            reel.tracks = []
            reel.background = nil
            reel.outputs = outputs.map { output in
                var output = output
                output.shape = nil
                return output
            }
            try await renderOnce(tape: reel, from: cut, log: log)
        }
    }

    /// Draws `demos`, each from its offset in milliseconds, on the layout's canvas, with their sound, for at least
    /// `atLeast` milliseconds (the director may talk on after the tracks are done); returns how long it runs.
    static func compose(
        _ demos: [(url: URL, offset: Int)], layout: TrackLayout, background: Background, frameRate: Int,
        atLeast: Int, to url: URL
    ) async throws -> Int {
        let composition = AVMutableComposition()
        var pictures: [CMPersistentTrackID] = []
        for demo in demos {
            let asset = AVURLAsset(url: demo.url)
            let length = try await asset.load(.duration)
            let at = CMTime(value: CMTimeValue(demo.offset), timescale: 1000)
            if let video = try await asset.loadTracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(
                   withMediaType: .video,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               )
            {
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: video, at: at)
                pictures.append(track.trackID)
            }
            for sound in try await asset.loadTracks(withMediaType: .audio) {
                try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
                    .insertTimeRange(CMTimeRange(start: .zero, duration: length), of: sound, at: at)
            }
        }
        // As long as the director talks: a still the compositor does not draw, under every track, holds the movie
        // open (an export drops empty time at the end), and each track's last frame is held over it.
        let end = CMTimeMaximum(composition.duration, CMTime(value: CMTimeValue(atLeast), timescale: 1000))
        if end > composition.duration {
            let filler = url.deletingLastPathComponent().appending(path: "filler.mov")
            try await StillClip.write(.standard, size: CGSize(width: 64, height: 64), seconds: end.seconds, to: filler)
            defer { try? FileManager.default.removeItem(at: filler) }
            let asset = AVURLAsset(url: filler)
            if let still = try await asset.loadTracks(withMediaType: .video).first,
               let track = composition.addMutableTrack(
                   withMediaType: .video,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               )
            {
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: end), of: still, at: .zero)
            }
        }
        let image: CIImage? = switch background {
        case let .image(url): CIImage(contentsOf: url)
        case let .video(url): try? await stillOf(url)
        case .color: nil
        }
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = TracksCompositor.self
        video.renderSize = layout.canvas
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        video.instructions = [TracksInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration), pictures: pictures, layout: layout,
            background: background, image: image
        )]
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleProRes422LPCM)
        else { throw ReelError("cannot draw the tracks together") }
        session.videoComposition = video
        try? FileManager.default.removeItem(at: url)
        try await session.export(to: url, as: .mov)
        return Int((composition.duration.seconds * 1000).rounded())
    }

    /// A background video's first frame: tracks are drawn over a still for now.
    private static func stillOf(_ url: URL) async throws -> CIImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        let (frame, _) = try await generator.image(at: .zero)
        return CIImage(cgImage: frame)
    }
}

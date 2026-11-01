import AVFoundation
import CoreImage

/// What the compositor draws for the whole movie: each track's picture where the director has it, over the
/// background.
final class TracksInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    /// Each track's picture, in the layout's order; nil for one with none.
    let pictures: [CMPersistentTrackID?]
    let direction: Direction
    let background: Background
    let image: CIImage?

    init(
        timeRange: CMTimeRange, pictures: [CMPersistentTrackID?], direction: Direction, background: Background,
        image: CIImage?
    ) {
        self.timeRange = timeRange
        self.pictures = pictures
        self.direction = direction
        self.background = background
        self.image = image
        requiredSourceTrackIDs = pictures.compactMap { $0.map { NSNumber(value: $0) } }
    }
}

/// Draws every track's frame as a window where the director has it at that moment, the ones on top last. A track
/// that has not started yet is not drawn; one that has ended holds its last frame.
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
        let layout = instruction.direction.layout
        let canvas = CGRect(origin: .zero, size: layout.canvas)
        var image: CIImage = if let backdrop = instruction.image {
            FrameCompositor.fill(backdrop, into: canvas)
        } else if case let .color(r, g, b) = instruction.background {
            CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: canvas)
        } else {
            CIImage(color: .black).cropped(to: canvas)
        }
        let placements = instruction.direction.placements(at: request.compositionTime.seconds)
        let order = placements.indices.sorted { (placements[$0].z, $0) < (placements[$1].z, $1) }
        for index in order {
            guard let track = instruction.pictures[index] else { continue }
            let picture: CIImage? = lock.withLock {
                if let frame = request.sourceFrame(byTrackID: track) {
                    last[track] = CIImage(cvPixelBuffer: frame)
                }
                return last[track]
            }
            let placement = placements[index]
            guard let picture, let frame = placement.frame, placement.alpha > 0.01, frame.width >= 2,
                  frame.height >= 2
            else { continue }
            // Core Image's y runs up from the bottom; the layout's from the top.
            let slot = CGRect(
                x: frame.minX, y: layout.canvas.height - frame.maxY, width: frame.width, height: frame.height
            )
            var window = FrameCompositor.window(
                picture, in: slot, corner: layout.corner(index, at: frame), canvas: canvas
            )
            if placement.alpha < 1 {
                window = window.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: placement.alpha),
                ])
            }
            image = window.composited(over: image)
        }
        Self.context.render(image, to: output, bounds: canvas, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        request.finish(withComposedVideoFrame: output)
    }
}

/// A reel of tracks with every track rendered: what composing them on a canvas needs.
struct RenderedTracks {
    /// The director's take: what was said over the tracks, and when.
    var director: Take
    /// Each track's demo, losslessly, and where it starts on the director's clock.
    var demos: [(url: URL, take: Take, offset: Int)]
    /// The director's moves, each at the end of the step before it, as a caption is.
    var moves: [(at: Double, move: Move, transition: Transition?)]
    var frameRate: Int

    /// The tracks laid out on the canvas of `shape`, the smallest that holds them as `Framing` would.
    func layout(of tape: Tape, shape: Output.Shape, padding: Double) -> TrackLayout {
        TrackLayout.make(
            names: tape.tracks.map(\.name), sizes: demos.map { CGSize(width: $0.take.width, height: $0.take.height) },
            scales: demos.map(\.take.scale), shape: shape, padding: padding, arrangement: tape.layout
        )
    }

    func removeDemos() {
        demos.forEach { try? FileManager.default.removeItem(at: $0.url) }
    }
}

extension Renderer {
    /// A reel of tracks: each track rendered as its own reel renders it (its overlays, its cuts), then all of them
    /// drawn together on one canvas for each shape its Outputs take, lined up by when each started. That movie is
    /// then the director's take: narration, captions, the intro and outro go on it as on any take.
    static func renderTracks(tape: Tape, from location: TakeLocation, log: (String) -> Void) async throws {
        let rendered = try await renderTrackDemos(tape: tape, from: location, log: log)
        defer { rendered.removeDemos() }

        // One composed take for each shape the Outputs take, each then rendered as any take is.
        let shapes = Dictionary(grouping: tape.outputs) { $0.shape ?? .aspect(16, 9) }
        for (shape, outputs) in shapes.sorted(by: { $0.key.description < $1.key.description }) {
            let cut = try await composeTracks(
                rendered, of: tape, from: location, shape: shape, padding: tape.padding,
                background: tape.background ?? .standard
            )
            // The director's reel, its tracks already drawn: its Outputs of this shape, bare, on the canvas above.
            var reel = directorReel(of: tape)
            reel.outputs = outputs.map { output in
                var output = output
                output.shape = nil
                return output
            }
            try await renderOnce(tape: reel, from: cut, log: log)
        }
    }

    /// Every track of a reel of tracks rendered as its own reel renders it, losslessly, next to the take, with the
    /// director's take and moves.
    static func renderTrackDemos(tape: Tape, from location: TakeLocation, log: (String) -> Void) async throws
        -> RenderedTracks
    {
        let directorURL = Tracks.director(in: location)
        guard let data = try? Data(contentsOf: directorURL),
              let director = try? JSONDecoder().decode(Take.self, from: data)
        else {
            throw ReelError("this reel has no take yet: record it (reel record), or record and render with reel run")
        }
        var demos: [(url: URL, take: Take, offset: Int)] = []
        do {
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
        } catch {
            demos.forEach { try? FileManager.default.removeItem(at: $0.url) }
            throw error
        }
        let frameRate = demos.map(\.take.frameRate).max() ?? tape.frameRate
        let moves = zip(tape.steps, Anchors.times(tape: directorReel(of: tape), take: director))
            .compactMap { step, at in
                if case let .move(move, transition) = step.command { (at, move, transition) } else { nil }
            }
        return RenderedTracks(director: director, demos: demos, moves: moves, frameRate: frameRate)
    }

    /// The tracks drawn together on the canvas of `shape`, into a take of their own under `cuts/` next to the
    /// reel's: the director's events over a movie of every track where the director has it.
    static func composeTracks(
        _ rendered: RenderedTracks, of tape: Tape, from location: TakeLocation, shape: Output.Shape,
        padding: Double, background: Background
    ) async throws -> TakeLocation {
        let (director, demos) = (rendered.director, rendered.demos)
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
        let layout = rendered.layout(of: tape, shape: shape, padding: padding)
        let direction = Direction.make(
            layout: layout, start: tape.layout, starts: demos.map { Double($0.offset) / 1000 }, moves: rendered.moves
        )
        let length = try await compose(
            demos.map { ($0.url, $0.offset) }, direction: direction, background: background,
            frameRate: rendered.frameRate, atLeast: director.durationMs, to: cut.movie
        )
        var take = Take(
            width: Int(layout.canvas.width), height: Int(layout.canvas.height),
            scale: demos.map(\.take.scale).max() ?? 2, frameRate: rendered.frameRate,
            audio: demos.contains(where: \.take.audio), durationMs: max(director.durationMs, length),
            events: director.events
        )
        take.startedAt = director.startedAt
        try cut.write(take)
        return cut
    }

    /// The director's reel with its tracks drawn already: what renders a composed take, on no backdrop of its own.
    static func directorReel(of tape: Tape) -> Tape {
        var reel = tape
        reel.tracks = []
        reel.background = nil
        return reel
    }

    /// Draws `demos`, each from its offset in milliseconds, on the layout's canvas, with their sound, for at least
    /// `atLeast` milliseconds (the director may talk on after the tracks are done); returns how long it runs.
    static func compose(
        _ demos: [(url: URL, offset: Int)], direction: Direction, background: Background, frameRate: Int,
        atLeast: Int, to url: URL
    ) async throws -> Int {
        let composition = AVMutableComposition()
        var pictures: [CMPersistentTrackID?] = []
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
            } else {
                pictures.append(nil)
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
        video.renderSize = direction.layout.canvas
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        video.instructions = [TracksInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration), pictures: pictures,
            direction: direction,
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

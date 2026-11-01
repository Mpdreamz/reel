import AVFoundation
import Foundation

/// A reel of scenes: other reels (`Include`), each recorded as its own reel is, into its own take next to it, and
/// joined in render on one canvas with the transitions between them, the sequence's intro and outro around them. An
/// app, a web page, a code screen, a terminal and a reel of tracks can so share one video, each scene keeping its own
/// narration, captions, zooms and cuts.
public enum Scenes {
    /// Each scene's reel, read.
    public static func load(_ tape: Tape) throws -> [(scene: Scene, tape: Tape)] {
        try tape.scenes.map { scene in
            let read: Tape
            do {
                read = try Tape.load(scene.url)
            } catch let error as TapeError {
                throw TapeError(
                    message: "\(scene.url.lastPathComponent)\(error.line.map { " line \($0)" } ?? ""): \(error.message)"
                )
            }
            guard !read.launch.isSequence else {
                throw TapeError(
                    message: "\(scene.url.lastPathComponent) joins scenes itself; a scene cannot join scenes"
                )
            }
            return (scene, read)
        }
    }

    /// A scene's reel as a sequence read for `profile` renders it: read for the same profile when the scene knows
    /// one by that name (the built-in ones, or its own), as it is when it does not.
    static func tape(_ read: Tape, for profile: Profile?) throws -> Tape {
        guard let profile, let own = read.profile(named: profile.name) else { return read }
        return try read.with(profile: own)
    }

    /// Records every scene, in order, each into its own take (`.reel/<scene>/` next to its reel); a reel of tracks
    /// records them all at once, as it does on its own.
    public static func record(_ tape: Tape, log: @escaping @Sendable (String) -> Void) async throws {
        let scenes = try load(tape)
        for (index, (scene, read)) in scenes.enumerated() {
            log("scene \(index + 1) of \(scenes.count): \(scene.url.lastPathComponent)")
            read.warnings.forEach { log("warning: \($0)") }
            if read.isTracks {
                try await Tracks.record(read, into: TakeLocation(tape: scene.url), log: log)
            } else {
                _ = try await Recorder.record(read, into: TakeLocation(tape: scene.url), log: log)
            }
        }
    }
}

extension Tape {
    /// A reel of tracks: several subjects recorded at once and drawn together.
    var isTracks: Bool {
        launch.isTogether && !tracks.isEmpty
    }
}

extension Renderer {
    /// A sequence's Outputs: each scene rendered as its own reel renders it (for the same profile, when the scene
    /// knows it), framed on one canvas, joined with the transitions between them, the intro and outro around them.
    static func renderScenes(tape: Tape, from location: TakeLocation, log: (String) -> Void) async throws {
        let scenes = try Scenes.load(tape)
        let directory = location.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        /// A scene's demo: its take cut, zoomed, narrated and drawn over, losslessly; or a reel of tracks, each track
        /// rendered so, drawn together once the canvas is known.
        enum Demo {
            case take(URL, Take)
            case tracks(RenderedTracks, tape: Tape, location: TakeLocation)
        }
        var demos: [(demo: Demo, transition: SectionTransition?)] = []
        defer {
            for (demo, _) in demos {
                switch demo {
                case let .take(url, _): try? FileManager.default.removeItem(at: url)
                case let .tracks(rendered, _, _): rendered.removeDemos()
                }
            }
        }
        for (index, (scene, read)) in scenes.enumerated() {
            let name = scene.url.lastPathComponent
            let sceneTape = try Scenes.tape(read, for: tape.profile)
            let sceneLocation = TakeLocation(tape: scene.url)
            let taken = sceneTape.isTracks ? Tracks.director(in: sceneLocation) : sceneLocation.timeline
            guard FileManager.default.fileExists(atPath: taken.path) else {
                throw ReelError("scene \(index + 1), \(name), has no take yet: record it (reel record \(name)), or "
                    + "record every scene with reel run")
            }
            if sceneTape.isTracks {
                let rendered: RenderedTracks
                do {
                    rendered = try await renderTrackDemos(tape: sceneTape, from: sceneLocation, log: log)
                } catch {
                    throw ReelError("scene \(index + 1), \(name): \(error.localizedDescription)")
                }
                demos.append((.tracks(rendered, tape: sceneTape, location: sceneLocation), scene.transition))
                continue
            }
            let prepared: Prepared
            do {
                prepared = try await prepare(tape: sceneTape, from: sceneLocation, log: log)
            } catch let error as TapeError {
                throw ReelError("scene \(index + 1), \(name): \(error.description)")
            }
            let url = directory.appending(path: "scene-\(index + 1).mov")
            try await render(
                sceneLocation.movie, take: prepared.take, overlays: prepared.overlays,
                soundtrack: prepared.soundtrack, cut: prepared.cut, to: Output(url: url, format: .mov), lossless: true
            )
            demos.append((.take(url, prepared.take), scene.transition))
        }
        let frameRate = demos.map { demo in
            switch demo.demo {
            case let .take(_, take): take.frameRate
            case let .tracks(rendered, _, _): rendered.frameRate
            }
        }.max() ?? Tape.defaultFrameRate

        /// The shape scenes are joined in: the Output's own, else 16:9. Scenes differ in size, so they always sit on
        /// a canvas.
        func shape(_ output: Output) -> Output.Shape {
            output.shape ?? .aspect(16, 9)
        }
        func key(_ output: Output) -> String {
            shape(output).description
        }

        func finish(_ output: Output, _ url: URL) async throws {
            let background = tape.background ?? .standard
            // One canvas for every scene: the largest any of them needs at this shape, each scene fitted on it.
            let canvases = demos.map { demo in
                switch demo.demo {
                case let .take(_, take):
                    Framing.make(
                        recording: CGSize(width: take.width, height: take.height), scale: take.scale,
                        shape: shape(output), padding: tape.padding, background: background
                    ).canvas
                case let .tracks(rendered, sceneTape, _):
                    rendered.layout(of: sceneTape, shape: shape(output), padding: tape.padding).canvas
                }
            }
            let canvas = canvases.max { $0.width * $0.height < $1.width * $1.height } ?? CGSize(
                width: 1920,
                height: 1080
            )
            let tag = key(output).replacingOccurrences(of: ":", with: "x")
            var joined: URL?
            var made: [URL] = []
            defer { made.forEach { try? FileManager.default.removeItem(at: $0) } }
            for (index, demo) in demos.enumerated() {
                let framed = directory.appending(path: "framed-\(tag)-\(index + 1).mov")
                made.append(framed)
                let size = Output.Shape.size(Int(canvas.width), Int(canvas.height))
                switch demo.demo {
                case let .take(url, take):
                    try await Framer.frame(
                        url,
                        with: Framing.make(
                            recording: CGSize(width: take.width, height: take.height), scale: take.scale,
                            shape: size, padding: tape.padding, background: background
                        ),
                        frameRate: frameRate, to: Output(url: framed, format: .mov), lossless: true
                    )
                case let .tracks(rendered, sceneTape, sceneLocation):
                    // Drawn together on the canvas itself, on the sequence's backdrop, then narrated and captioned as
                    // the reel's director would have it, without its intro and outro.
                    let cut = try await composeTracks(
                        rendered, of: sceneTape, from: sceneLocation, shape: size, padding: tape.padding,
                        background: background
                    )
                    let prepared = try await prepare(tape: directorReel(of: sceneTape), from: cut, log: log)
                    try await render(
                        cut.movie, take: prepared.take, overlays: prepared.overlays, soundtrack: prepared.soundtrack,
                        cut: prepared.cut, to: Output(url: framed, format: .mov), lossless: true
                    )
                }
                guard let before = joined else {
                    joined = framed
                    continue
                }
                // The next scene comes in as the one before's outro would: its own sound, the transition between.
                let next = directory.appending(path: "joined-\(tag)-\(index + 1).mov")
                made.append(next)
                try await Assembler.assemble(
                    main: before, intro: nil,
                    outro: Section(
                        title: "", subtitle: nil, duration: nil, background: .video(framed),
                        transition: demo.transition ?? .standard
                    ),
                    frameRate: frameRate, in: directory, to: Output(url: next, format: .mov), lossless: true
                )
                joined = next
            }
            guard let joined else { throw ReelError("a reel of scenes needs at least one Include") }
            if tape.intro != nil || tape.outro != nil {
                try await Assembler.assemble(
                    main: joined, intro: tape.intro, outro: tape.outro, frameRate: frameRate, in: directory,
                    to: Output(url: url, format: .mov, shape: output.shape), lossless: true
                )
            } else {
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.copyItem(at: joined, to: url)
            }
        }

        try await writeOutputs(of: tape, frameRate: frameRate, in: directory, key: key, finish: finish, log: log)
    }
}

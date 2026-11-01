import AVFoundation
import Foundation

/// A reel of scenes: other reels (`Include`), each recorded as its own reel is, into its own take next to it, and
/// joined in render on one canvas with the transitions between them, the sequence's intro and outro around them. An
/// app, a web page, a code screen and a terminal can so share one video, each scene keeping its own narration,
/// captions, zooms and cuts.
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
                    message: "\(scene.url.lastPathComponent) joins scenes itself; a scene is a reel that records one thing"
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

    /// The size a sequence's scenes are framed and joined at: `canvas`, the largest any scene needs, made no wider
    /// than the widest of `outputs` will be written (`Set VideoWidth`, `Set GifWidth`), so nothing larger than what
    /// is kept goes through every pass. Movies are written at this size as they would be from the full canvas
    /// (`Encoding.size`).
    static func workingSize(of canvas: CGSize, for outputs: [Output], encoding: Encoding, gifWidth: Int) -> CGSize {
        var widest = 0
        for output in outputs {
            if output.format == .gif {
                widest = max(widest, gifWidth)
            } else if let width = encoding.width {
                widest = max(widest, width)
            } else {
                return canvas
            }
        }
        guard widest > 0 else { return canvas }
        var capped = encoding
        capped.width = widest
        return capped.size(for: canvas)
    }

    /// Records every scene, in order, each into its own take (`.reel/<scene>/` next to its reel).
    public static func record(_ tape: Tape, log: (String) -> Void) async throws {
        let scenes = try load(tape)
        for (index, (scene, read)) in scenes.enumerated() {
            log("scene \(index + 1) of \(scenes.count): \(scene.url.lastPathComponent)")
            read.warnings.forEach { log("warning: \($0)") }
            _ = try await Recorder.record(read, into: TakeLocation(tape: scene.url), log: log)
        }
    }
}

extension Renderer {
    /// A sequence's Outputs: each scene rendered as its own reel renders it (for the same profile, when the scene
    /// knows it), framed on one canvas, joined with the transitions between them, the intro and outro around them.
    static func renderScenes(tape: Tape, from location: TakeLocation, log: (String) -> Void) async throws {
        let scenes = try Scenes.load(tape)
        let directory = location.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Each scene's demo: its take cut, zoomed, narrated and drawn over, losslessly.
        var demos: [(url: URL, take: Take, transition: SectionTransition?)] = []
        for (index, (scene, read)) in scenes.enumerated() {
            let name = scene.url.lastPathComponent
            let sceneTape = try Scenes.tape(read, for: tape.profile)
            let sceneLocation = TakeLocation(tape: scene.url)
            guard FileManager.default.fileExists(atPath: sceneLocation.timeline.path) else {
                throw ReelError("scene \(index + 1), \(name), has no take yet: record it (reel record \(name)), or "
                    + "record every scene with reel run")
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
            demos.append((url, prepared.take, scene.transition))
        }
        defer { demos.forEach { try? FileManager.default.removeItem(at: $0.url) } }
        let frameRate = demos.map(\.take.frameRate).max() ?? Tape.defaultFrameRate

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
                Framing.make(
                    recording: CGSize(width: demo.take.width, height: demo.take.height), scale: demo.take.scale,
                    shape: shape(output), padding: tape.padding, background: background
                ).canvas
            }
            let largest = canvases.max { $0.width * $0.height < $1.width * $1.height } ?? CGSize(
                width: 1920,
                height: 1080
            )
            let canvas = Scenes.workingSize(
                of: largest, for: tape.outputs.filter { key($0) == key(output) }, encoding: tape.encoding,
                gifWidth: tape.gifWidth
            )
            let tag = key(output).replacingOccurrences(of: ":", with: "x")
            var joined: URL?
            var made: [URL] = []
            defer { made.forEach { try? FileManager.default.removeItem(at: $0) } }
            for (index, demo) in demos.enumerated() {
                let framed = directory.appending(path: "framed-\(tag)-\(index + 1).mov")
                made.append(framed)
                try await Framer.frame(
                    demo.url,
                    with: Framing.make(
                        recording: CGSize(width: demo.take.width, height: demo.take.height), scale: demo.take.scale,
                        shape: .size(Int(canvas.width), Int(canvas.height)), padding: tape.padding,
                        background: background
                    ),
                    frameRate: frameRate, to: Output(url: framed, format: .mov), lossless: true
                )
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

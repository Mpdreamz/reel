import AVFoundation
import ImageIO
@testable import ReelCore
import Testing

private let dir = URL(fileURLWithPath: "/tmp/reel-profile-tests")

private func parse(_ text: String) throws -> Tape {
    try Tape.parse(text, relativeTo: dir)
}

private func failure(_ text: String) -> TapeError? {
    do {
        _ = try parse(text)
        return nil
    } catch {
        return error as? TapeError
    }
}

private func failure(_ work: () throws -> some Any) -> String? {
    do {
        _ = try work()
        return nil
    } catch {
        return (error as? TapeError)?.message ?? "\(error)"
    }
}

/// Profiles and the settings they are made of, as the tape reads them.
struct ProfileTests {
    @Test func outputSettings() throws {
        let tape = try parse("""
        Launch x
        Output a.mp4
        Output@1:1 b.mp4
        Output c.gif
        Set VideoFrameRate 30
        Set MaxSize 1.5GB
        Set MaxLength 140s
        Set Shape 9:16
        Set Formats mp4, mov
        """)
        #expect(tape.videoFrameRate == 30)
        #expect(tape.maxSize == 1_500_000_000)
        #expect(tape.maxLength == 140)
        // The shape frames what names none of its own; the GIF is left out.
        #expect(tape.outputs.map(\.shape) == [.aspect(9, 16), .aspect(1, 1)])
        #expect(tape.skipped.map(\.url.lastPathComponent) == ["c.gif"])
    }

    @Test func sizesCountInThousands() {
        #expect(parseBytes("10MB") == 10_000_000)
        #expect(parseBytes("500kb") == 500_000)
        #expect(parseBytes("1.5GB") == 1_500_000_000)
        #expect(parseBytes("10") == nil)
        #expect(parseBytes("0MB") == nil)
        #expect(parseBytes("MB") == nil)
    }

    @Test(arguments: [
        ("Launch x\nOutput a.mp4\nSet MaxSize ten", "MaxSize must be a size such as 10MB, 500KB or 1.5GB, not 'ten'"),
        ("Launch x\nOutput a.mp4\nSet MaxLength 0s", "MaxLength must be longer than nothing"),
        (
            "Launch x\nOutput a.mp4\nSet VideoFrameRate 0",
            "VideoFrameRate must be a whole number from 1 to 120, not '0'"
        ),
        ("Launch x\nOutput a.mp4\nSet Formats mp4, webm", "Formats lists mp4, mov or gif, not 'webm'"),
        ("Launch x\nOutput a.mp4\nSet Profiles github github", "Profiles names a profile twice"),
        ("Launch x\nOutput a.mp4\nSet Quality 1 2", "expected Set <setting> <value>"),
    ])
    func errors(text: String, message: String) {
        #expect(failure(text) == TapeError(line: 3, message: message))
    }

    @Test func anUnknownProfileIsRefusedWithWhereItWasNamed() {
        #expect(failure("Launch x\nOutput a.mp4\nSet Profiles github, tiktok")?.description
            == "line 3: there is no profile 'tiktok'; there are highest, github, web, social, feed or square")
    }

    @Test func aProfileAppliesOverTheTapeAndNamesItsOutputs() throws {
        let tape = try parse("""
        Launch x
        Output demo.mp4
        Output@1:1 square.mp4
        Output demo.gif
        Set Quality 50
        Set GifColors 64
        Set Profiles github, social
        """)
        #expect(tape.profiles == ["github", "social"])
        let social = try tape.with(profile: Profile.named("social"))
        // Its settings beat the tape's own; what it does not set stays the tape's.
        #expect(social.encoding == Encoding(quality: 70, codec: .h264, width: nil))
        #expect(social.gifColors == 64)
        #expect(social.videoFrameRate == 30)
        #expect(social.maxSize == 250_000_000)
        #expect(social.maxLength == 180)
        #expect(social.voice.subtitles)
        // Its shape frames the Outputs with none of their own, and it writes no GIF.
        #expect(social.outputs.map(\.url.lastPathComponent) == ["demo-social.mp4", "square-social.mp4"])
        #expect(social.outputs.map(\.shape) == [.size(1080, 1920), .aspect(1, 1)])
        #expect(social.skipped.map(\.url.lastPathComponent) == ["demo.gif"])
        let github = try tape.with(profile: Profile.named("github"))
        #expect(github.encoding == Encoding(quality: 50, codec: .h264, width: 1920))
        #expect(github.outputs.map(\.url.lastPathComponent) == [
            "demo-github.mp4",
            "square-github.mp4",
            "demo-github.gif",
        ])
        #expect(github.outputs.map(\.shape) == [nil, .aspect(1, 1), nil])
        // Read for no profile, it is itself.
        #expect(try tape.with(profile: nil) == tape)
    }

    @Test func whichProfilesRender() throws {
        let plain = try parse("Launch x\nOutput a.mp4")
        #expect(try plain.profilesToRender(chosen: []) == [nil])
        #expect(try plain.profilesToRender(chosen: ["web"]) == [Profile.named("web")])
        let listed = try parse("Launch x\nOutput a.mp4\nSet Profiles github, social")
        #expect(try listed.profilesToRender(chosen: []) == [Profile.named("github"), Profile.named("social")])
        #expect(try listed.profilesToRender(chosen: ["social"]) == [Profile.named("social")])
        #expect(failure { try listed.profilesToRender(chosen: ["feed"]) }
            == "the tape renders github, social; 'feed' is not one of them")
        #expect(failure { try plain.profilesToRender(chosen: ["tiktok"]) }
            == "there is no profile 'tiktok'; there are highest, github, web, social, feed or square")
    }

    @Test func everyBuiltInProfileReadsOnAnAppAndAWebTape() throws {
        for profile in Profile.builtIn {
            for opening in ["Launch x", "Open https://example.com"] {
                let tape = try parse("\(opening)\nOutput a.mp4\nOutput a.mov\nOutput a.gif")
                let read = try tape.with(profile: profile)
                #expect(read.profile == profile)
                #expect(read.outputs.count + read.skipped.count == 3)
            }
        }
    }

    @Test func aProfileNamesItsFilesBeforeTheExtension() {
        let url = URL(fileURLWithPath: "/m/demo.v2.mp4")
        #expect(Profile.named("github")?.suffixed(url).path == "/m/demo.v2-github.mp4")
    }
}

/// Movies and GIFs fitted under a size, thinned to a frame rate, and rendered for profiles.
struct FittingTests {
    let writer = TakeWriterTests()

    @Test func aMovieOverItsSizeIsEncodedAgainUnderIt() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 1, audio: false, noise: true)
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        let free = try await Encoder.encode(movie, to: output, with: .standard, frameRate: 30)
        let limit = free.bytes / 3
        let fitted = try await Encoder.fit(movie, to: output, with: .standard, frameRate: 30, under: limit)
        #expect(fitted.bytes <= limit)
        #expect(fitted.encodes >= 2)
        #expect(fitted.encoding.bitrate != nil)
        #expect(fitted.bytes == fileSize(output.url))
        // Already under: encoded once, at its quality.
        let roomy = try await Encoder.fit(movie, to: output, with: .standard, frameRate: 30, under: free.bytes * 2)
        #expect(roomy.encodes == 1)
        #expect(roomy.encoding.bitrate == nil)
    }

    @Test func aMovieThatCannotFitFailsAndLeavesNothing() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 1, audio: false, noise: true)
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        await #expect(throws: ReelError.self) {
            try await Encoder.fit(movie, to: output, with: .standard, frameRate: 30, under: 2000)
        }
        #expect(!FileManager.default.fileExists(atPath: output.url.path))
    }

    @Test func fewerFramesASecondKeepTheLength() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 1, audio: false)
        // Counted, not assumed: the encoder on CI's virtual machines need not keep every frame a test writes.
        let source = try await frames(in: AVURLAsset(url: movie))
        let thinned = Output(url: dir.appending(path: "thinned.mp4"), format: .mp4)
        try await Encoder.encode(
            movie, to: thinned, with: Encoding(quality: 65, codec: .h264, width: nil, frameRate: 10), frameRate: 30
        )
        let asset = AVURLAsset(url: thinned.url)
        #expect(try await abs(asset.load(.duration).seconds - 1) < 0.05)
        let kept = try await frames(in: asset)
        // A third of the source's, the first of each three: 10 of 30.
        #expect(kept == (source + 2) / 3, "\(kept) of \(source) frames")
        // Never more than the movie has: a rate above its own keeps what it has.
        let all = Output(url: dir.appending(path: "all.mp4"), format: .mp4)
        try await Encoder.encode(
            movie, to: all, with: Encoding(quality: 65, codec: .h264, width: nil, frameRate: 60), frameRate: 30
        )
        let unthinned = try await frames(in: AVURLAsset(url: all.url))
        let plain = Output(url: dir.appending(path: "plain.mp4"), format: .mp4)
        try await Encoder.encode(movie, to: plain, with: .standard, frameRate: 30)
        #expect(try await unthinned == frames(in: AVURLAsset(url: plain.url)), "\(unthinned) of \(source) frames")
        #expect(unthinned > kept * 2)
    }

    @Test func proResInAMovAndH264AtTheBestInAnMp4() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 0.5, audio: true)
        let prores = Encoding(quality: 100, codec: .prores, width: nil)
        let mov = Output(url: dir.appending(path: "out.mov"), format: .mov)
        try await Encoder.encode(movie, to: mov, with: prores, frameRate: 30)
        #expect(try await codec(of: mov.url) == kCMVideoCodecType_AppleProRes422)
        let mp4 = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        let result = try await Encoder.encode(movie, to: mp4, with: prores, frameRate: 30)
        #expect(try await codec(of: mp4.url) == kCMVideoCodecType_H264)
        #expect(result.encoding == Encoding(quality: 100, codec: .h264, width: nil))
    }

    @Test func aGifOverItsSizeIsDrawnSmallerUnderIt() async throws {
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 0.3, audio: false, noise: true)
        let gif = dir.appending(path: "out.gif")
        let look = GifWriter.Look(frameRate: 15, width: 320, colors: 256)
        let free = try await GifWriter.fit(from: movie, to: gif, look: look, under: nil)
        let fitted = try await GifWriter.fit(from: movie, to: gif, look: look, under: free.bytes / 3)
        #expect(fitted.bytes <= free.bytes / 3)
        #expect(fitted.writes > 1)
        #expect(fitted.look != look)
        await #expect(throws: ReelError.self) {
            try await GifWriter.fit(from: movie, to: gif, look: look, under: 100)
        }
        #expect(!FileManager.default.fileExists(atPath: gif.path))
    }

    @Test func aGifShrinksColoursFirstThenFramesThenWidth() {
        var look = GifWriter.Look(frameRate: 15, width: 800, colors: 256)
        look = look.smaller(than: 1.2)
        #expect(look == GifWriter.Look(frameRate: 15, width: 800, colors: 128))
        look = look.smaller(than: 1.2)
        #expect(look == GifWriter.Look(frameRate: 15, width: 800, colors: 64))
        look = look.smaller(than: 1.2)
        #expect(look == GifWriter.Look(frameRate: 10, width: 800, colors: 64))
        look = look.smaller(than: 4)
        #expect(look == GifWriter.Look(frameRate: 10, width: 380, colors: 64))
        // Far over, a cheap step is not enough: it narrows too.
        #expect(GifWriter.Look(frameRate: 15, width: 800, colors: 256).smaller(than: 4)
            == GifWriter.Look(frameRate: 15, width: 380, colors: 128))
        // Never narrower than 160.
        #expect(GifWriter.Look(frameRate: 10, width: 200, colors: 64).smaller(than: 100).width == 160)
    }

    @Test func aTapeRendersOnceForEachProfile() async throws {
        let dir = try writer.temporaryDirectory()
        let location = TakeLocation(tape: dir.appending(path: "demo.reel"))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try await writer.writeTake(to: location.movie, seconds: 1, audio: false)
        try location.write(Take(
            width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 1000,
            events: [Take.Event(line: 5, command: "Sleep 1s", startMs: 0, endMs: 1000)]
        ))
        let tape = try Tape.parse(
            "Launch x\nOutput demo.mp4\nOutput demo.gif\nSet Profiles github, social\nSleep 1s", relativeTo: dir
        )
        var lines: [String] = []
        try await Renderer.render(tape: tape, from: location, log: { lines.append($0) })
        let written = try Set(FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(written.isSuperset(of: ["demo-github.mp4", "demo-github.gif", "demo-social.mp4"]))
        #expect(!written.contains("demo-social.gif"))
        #expect(!written.contains("demo.mp4"))
        #expect(lines.contains("skipped demo.gif: social writes no .gif"))
        // Social frames the take on a canvas of exactly 1080x1920.
        let social = try #require(try await AVURLAsset(url: dir.appending(path: "demo-social.mp4"))
            .loadTracks(withMediaType: .video).first)
        #expect(try await social.load(.naturalSize) == CGSize(width: 1080, height: 1920))
        // Only the profiles asked for, from among the tape's.
        lines = []
        try await Renderer.render(tape: tape, from: location, profiles: ["github"], log: { lines.append($0) })
        #expect(lines.allSatisfy { !$0.contains("social") })
    }

    @Test func aMovieLongerThanItsMostIsRefused() async throws {
        let dir = try writer.temporaryDirectory()
        let location = TakeLocation(tape: dir.appending(path: "demo.reel"))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try await writer.writeTake(to: location.movie, seconds: 2, audio: false)
        try location.write(Take(
            width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 2000,
            events: [Take.Event(line: 4, command: "Sleep 2s", startMs: 0, endMs: 2000)]
        ))
        let tape = try Tape.parse("Launch x\nOutput demo.mp4\nSet MaxLength 1s\nSleep 2s", relativeTo: dir)
        await #expect {
            try await Renderer.render(tape: tape, from: location, log: { _ in })
        } throws: { error in
            "\(error)".contains("demo.mp4 would run 0:02, longer than MaxLength 0:01")
        }
    }

    private func frames(in asset: AVAsset) async throws -> Int {
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(buffer) > 0 { count += 1 }
        }
        return count
    }

    private func codec(of url: URL) async throws -> FourCharCode? {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        return try await track.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
    }
}

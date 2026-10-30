import Foundation
@testable import ReelCore
import Testing

/// A repository in a temporary folder: a `.git` at its root, files written into it by relative path.
private struct Repo {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "reel-repo-\(UUID().uuidString)")
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ path: String, _ text: String) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func tape(_ path: String, _ text: String) throws -> Tape {
        try Tape.load(write(path, text))
    }

    func failure(_ path: String, _ text: String) -> String? {
        do {
            _ = try tape(path, text)
            return nil
        } catch {
            return "\(error)"
        }
    }
}

struct ImportTests {
    @Test func doubleSlashStartsAtTheGitRoot() throws {
        let repo = try Repo()
        let tape = try repo.tape(
            "demos/deep/a.reel",
            "Launch x\nOutput //docs/media/a.mp4\nSet Background //design/bg.png"
        )
        #expect(tape.outputs[0].url.path == repo.root.appending(path: "docs/media/a.mp4").path)
        #expect(tape.background == .image(repo.root.appending(path: "design/bg.png")))
        #expect(tape.warnings.isEmpty)
    }

    @Test func doubleSlashOutsideARepositoryIsRefused() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "reel-norepo-\(UUID().uuidString)")
        #expect(throws: TapeError(
            line: 2,
            message: "//a.mp4 starts at the git root (//), but \(dir.path) is in no git repository"
        )) {
            try Tape.parse("Launch x\nOutput //a.mp4", relativeTo: dir)
        }
    }

    @Test func aRelativePathOutOfTheRepositoryIsWarnedAbout() throws {
        let repo = try Repo()
        let tape = try repo.tape("demos/a.reel", """
        Launch ../../elsewhere/App.app
        Output ../docs/a.mp4
        Output ../../outside.mp4
        Output ~/Movies/home.mp4
        Output /tmp/absolute.mp4
        """)
        // Only the relative ones that leave: inside, from home and absolute are as meant.
        #expect(tape.warnings == [
            "line 1: ../../elsewhere/App.app leads outside the git root \(repo.root.path), so it works only where that sits next to the repository",
            "line 3: ../../outside.mp4 leads outside the git root \(repo.root.path), so it works only where that sits next to the repository",
        ])
    }

    @Test func importedSettingsAreDefaultsTheTapeAndItsProfilesOverride() throws {
        let repo = try Repo()
        try repo.write("presets/house.reelpreset", """
        # The house look.
        Set Quality 50
        Set GifColors 64
        Set Background backdrop.png
        Set Voice system:Samantha
        """)
        let tape = try repo.tape("demos/a.reel", """
        Import //presets/house.reelpreset
        Launch x
        Output a.mp4
        Set GifColors 128
        """)
        #expect(tape.encoding.quality == 50)
        #expect(tape.gifColors == 128)
        // A path in a preset is from the preset.
        #expect(tape.background == .image(repo.root.appending(path: "presets/backdrop.png")))
        #expect(tape.voice.source == .system("Samantha"))
        // A profile beats both.
        #expect(try tape.with(profile: tape.profile(named: "web")).encoding.quality == 60)
    }

    @Test func importsComeFirstAndOnlyImportPresets() throws {
        let repo = try Repo()
        try repo.write("house.reelpreset", "Set Quality 50")
        try repo.write("other.reel", "Launch y\nOutput b.mp4")
        #expect(repo.failure("a.reel", "Launch x\nImport house.reelpreset\nOutput a.mp4")
            == "line 2: Import comes first, before Launch or Open")
        #expect(repo.failure("a.reel", "Import other.reel\nLaunch x\nOutput a.mp4")
            == "line 1: other.reel is not a .reelpreset; Import reads presets, not tapes")
        #expect(repo.failure("a.reel", "Import missing.reelpreset\nLaunch x\nOutput a.mp4")
            == "line 1: cannot read \(repo.root.path)/missing.reelpreset")
        // Comments may come before.
        #expect(try repo.tape("b.reel", "# demo\nImport house.reelpreset\nLaunch x\nOutput a.mp4").encoding
            .quality == 50)
    }

    @Test func presetsImportPresetsInOrderAndNeverInALoop() throws {
        let repo = try Repo()
        try repo.write("base.reelpreset", "Set Quality 40\nSet GifColors 32")
        try repo.write("team.reelpreset", "Import base.reelpreset\nSet Quality 55")
        let tape = try repo.tape("a.reel", "Import team.reelpreset\nLaunch x\nOutput a.mp4")
        #expect(tape.encoding.quality == 55)
        #expect(tape.gifColors == 32)
        try repo.write("loop-a.reelpreset", "Import loop-b.reelpreset")
        try repo.write("loop-b.reelpreset", "Import loop-a.reelpreset")
        #expect(repo.failure("b.reel", "Import loop-a.reelpreset\nLaunch x\nOutput a.mp4")
            == "line 1: loop-a.reelpreset imports itself: loop-a.reelpreset → loop-b.reelpreset → loop-a.reelpreset")
        try repo.write("late.reelpreset", "Set Quality 50\nImport base.reelpreset")
        #expect(repo.failure("c.reel", "Import late.reelpreset\nLaunch x\nOutput a.mp4")
            == "line 1: late.reelpreset line 2: Import comes first, before any Set or Profile")
    }

    @Test func aPresetHoldsNothingThatRecords() throws {
        let repo = try Repo()
        try repo.write("bad.reelpreset", "Set Quality 50\nLaunch y")
        #expect(repo.failure("a.reel", "Import bad.reelpreset\nLaunch x\nOutput a.mp4")
            == "line 1: bad.reelpreset line 2: a preset holds Import, Set and Profile lines; Launch belongs in a tape")
        try repo.write("value.reelpreset", "Set Quality lots")
        #expect(repo.failure("b.reel", "Import value.reelpreset\nLaunch x\nOutput a.mp4")
            == "value.reelpreset line 1: Quality must be a whole number from 1 to 100, not 'lots'")
        // Read knowing what the tape records: a web setting in an app tape is refused, naming the preset.
        try repo.write("web.reelpreset", "Set Viewport 1280x800")
        #expect(repo.failure("c.reel", "Import web.reelpreset\nLaunch x\nOutput a.mp4")
            == "web.reelpreset line 1: Set Viewport is for web pages (Open); this tape Launches an app")
    }

    @Test func presetsDefineAndAmendProfiles() throws {
        let repo = try Repo()
        try repo.write("presets/house.reelpreset", """
        Set Quality 50

        Profile github
          Set GifColors 128

        Profile docs extends web "Our docs site"
          Set VideoWidth 1440

          Set Background docs.png
        Set GifWidth 600
        """)
        let tape = try repo.tape("demos/a.reel", """
        Import //presets/house.reelpreset
        Launch x
        Output a.mp4
        Output a.gif
        Set Profiles github, docs
        """)
        // The block ended at the first line that is not indented.
        #expect(tape.gifWidth == 600)
        let docs = try #require(tape.profile(named: "docs"))
        #expect(docs.purpose == "Our docs site")
        #expect(docs.settings.map(\.name) == ["VideoWidth", "Quality", "VideoFrameRate", "VideoWidth", "Background"])
        #expect(docs.settings.last?.origin == "house.reelpreset line 9")
        let forDocs = try tape.with(profile: docs)
        #expect(forDocs.encoding.width == 1440)
        #expect(forDocs.encoding.quality == 60)
        #expect(forDocs.background == .image(repo.root.appending(path: "presets/docs.png")))
        #expect(forDocs.outputs.map(\.url.lastPathComponent) == ["a-docs.mp4", "a-docs.gif"])
        let github = try tape.with(profile: tape.profile(named: "github"))
        #expect(github.gifColors == 128)
        #expect(github.maxSize == 10_000_000)
        #expect(try tape.profilesToRender(chosen: []).map { $0?.name } == ["github", "docs"])
    }

    @Test func aTapeDefinesProfilesToo() throws {
        let repo = try Repo()
        let tape = try repo.tape("a.reel", """
        Launch x
        Output a.mp4
        Profile slides "Conference slides"
          Set Shape 1920x1080
          Set VideoFrameRate 30
        Set Profiles slides
        Sleep 1s
        """)
        #expect(tape.profiles == ["slides"])
        #expect(tape.steps.count == 1)
        let slides = try tape.with(profile: tape.profile(named: "slides"))
        #expect(slides.outputs.map(\.shape) == [.size(1920, 1080)])
        #expect(slides.profile?.settings.first?.origin == "line 4")
    }

    @Test(arguments: [
        (
            "Profile docs\n  Set Size 800x600",
            "line 4: Size is fixed when recording, and one take serves every profile; set it outside the profile"
        ),
        ("Profile docs\n  Set Profiles web", "line 4: a profile cannot choose profiles; Set Profiles outside it"),
        ("Profile docs\n  Caption \"x\"", "line 4: a profile holds indented Set <setting> <value> lines"),
        (
            "Profile Docs\n  Set Quality 50",
            "line 3: a profile's name is lowercase letters, digits and dashes, such as docs or social-2, not 'Docs'"
        ),
        ("Profile gif\n  Set Quality 50", "line 3: gif is an Output's type; give the profile another name"),
        ("Profile docs", "line 3: Profile docs sets nothing; indent its Set lines under it"),
        (
            "Profile docs extends wiki\n  Set Quality 50",
            "line 3: there is no profile wiki to extend; there are highest, github, web, social, feed or square"
        ),
        (
            "Profile github extends web\n  Set Quality 50",
            "line 3: there is already a profile github; amend it with Profile github, or give the new one a name of its own"
        ),
    ])
    func profileErrors(block: String, message: String) throws {
        let repo = try Repo()
        #expect(repo.failure("a.reel", "Launch x\nOutput a.mp4\n\(block)") == message)
    }

    @Test func aProfilesBadValueIsRefusedNamingWhereItIs() throws {
        let repo = try Repo()
        try repo.write("house.reelpreset", "Profile docs\n  Set Quality lots")
        let tape = try repo.tape("a.reel", "Import house.reelpreset\nLaunch x\nOutput a.mp4\nSet Profiles docs")
        #expect(throws: TapeError(
            message: "profile docs (house.reelpreset line 2): Quality must be a whole number from 1 to 100, not 'lots'"
        )) {
            try tape.with(profile: tape.profile(named: "docs"))
        }
    }
}

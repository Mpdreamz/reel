import AppKit
import AVFoundation
import CoreMedia
import Foundation
@testable import ReelCore
import Testing
import WebKit

private let dir = URL(fileURLWithPath: "/tmp/demos")

private func tape(_ text: String) throws -> Tape {
    try Tape.parse(text, relativeTo: dir)
}

struct WebParsingTests {
    @Test func aWebTape() throws {
        let parsed = try tape("""
        Open https://example.com/start
        Output a.mp4
        Set Browser "/Applications/Brave Browser.app"
        Set Viewport 1000x700
        Click "Sign in"
        Click css:form .submit
        Wait #email
        Open site/next.html
        """.replacingOccurrences(of: "css:form .submit", with: "css:.submit"))
        #expect(parsed.launch == .web(URL(string: "https://example.com/start")!))
        #expect(parsed.web.browser == .app(URL(fileURLWithPath: "/Applications/Brave Browser.app")))
        #expect(parsed.web.viewport == CGSize(width: 1000, height: 700))
        #expect(parsed.steps.map(\.command) == [
            .click(.label("Sign in")), .click(.css(".submit")), .wait(.identifier("email")),
            .open(URL(fileURLWithPath: "/tmp/demos/site/next.html")),
        ])
        // A web tape needs no Accessibility: input goes to the page.
        #expect(parsed.launch.isWeb)
        #expect(try tape("Open file:///tmp/a.html\nOutput a.mp4").web == WebSettings())
    }

    @Test(arguments: [
        (
            "Open example.com\nOutput a.mp4",
            1,
            "'example.com' is not a web address; write https://…, http://…, file://… or a path to an .html file"
        ),
        ("Launch x\nOpen https://a.dev\nOutput a.mp4", 2, "Open goes to a web page; this reel Launches an app"),
        (
            "Open https://a.dev\nOutput a.mp4\nLaunch x",
            3,
            "a web reel Opens pages; line 1 already does, so there is no app to Launch"
        ),
        ("Launch x\nOutput a.mp4\nClick css:.buy", 3, "css: targets are for web pages; Open one instead of Launch"),
        (
            "Open https://a.dev\nSet Browser Chrome",
            2,
            "Browser is webkit, chromium or a Chromium-based .app such as /Applications/Brave Browser.app, not 'Chrome'"
        ),
        (
            "Open https://a.dev\nSet Viewport big",
            2,
            "Viewport must be <width>x<height> in points, such as 1280x800, not 'big'"
        ),
        ("Open https://a.dev\nOutput a.mp4\nClick css:", 3, "css: needs a selector after it, such as css:.pricing"),
        // A setting that does not fit what the tape records is refused, not ignored.
        ("Launch x\nSet Viewport 800x600", 2, "Set Viewport is for web pages (Open); this reel Launches an app"),
        ("Launch x\nSet Browser chromium", 2, "Set Browser is for web pages (Open); this reel Launches an app"),
        ("Open https://a.dev\nSet Size 800x600", 2, "Set Size is an app's window; a web page's size is Set Viewport"),
    ])
    func errors(text: String, line: Int, message: String) {
        #expect(throws: TapeError(line: line, message: message)) { try tape(text) }
    }
}

struct WebDriverTests {
    @Test func textBecomesASafeJavaScriptString() {
        #expect(WebDriver.literal("Sign in") == #""Sign in""#)
        #expect(WebDriver.literal(#"say "hi"\ </script>"#) == #""say \"hi\"\\ <\/script>""#)
    }

    @Test func findersAskForTheRightThing() throws {
        let label = try #require(WebDriver.finder(for: .label("Buy"), scroll: true))
        #expect(label.contains(#"{label: "Buy"}"#))
        #expect(label.contains("scrollIntoView"))
        #expect(try #require(WebDriver.finder(for: .css(".a > b"), scroll: false)).contains(#"{css: ".a > b"}"#))
        #expect(try !#require(WebDriver.finder(for: .identifier("x"), scroll: false)).contains("scrollIntoView"))
        #expect(WebDriver.finder(for: .point(.zero), scroll: false) == nil)
    }

    @Test func keysAsThePageSeesThem() throws {
        #expect(WebDriver.keys["return"]?.key == "Enter")
        #expect(WebDriver.keys["return"]?.text == "\r")
        #expect(WebDriver.keys["down"]?.keyCode == 40)
        #expect(WebDriver.keys["a"]?.code == "KeyA")
        #expect(WebDriver.keys["7"]?.code == "Digit7")
        #expect(WebDriver.keys["f5"]?.keyCode == 116)
        // macOS editing shortcuts are named commands to DevTools.
        #expect(try WebDriver.commands[#require(KeyCombo("cmd+a")).description] == "selectAll")
        #expect(try WebDriver.commands[#require(KeyCombo("cmd+shift+z")).description] == "redo")
    }

    @Test func aSelectorWithSpacesIsQuotedAfterTheColon() throws {
        let parsed =
            try tape(
                #"Open https://a.dev\#nOutput a.mp4\#nClick css:"form button[type=submit]"\#nClick "css:not a selector""#
            )
        #expect(parsed.steps.map(\.command) == [
            .click(.css("form button[type=submit]")), .click(.label("css:not a selector")),
        ])
        #expect(parsed.steps[0].source == #"Click css:"form button[type=submit]""#)
        // Unquoted, the space splits it: two words where Click takes one.
        #expect(throws: TapeError(line: 3, message: "expected Click \"<label>\", Click #<identifier> or Click @x,y")) {
            try tape("Open https://a.dev\nOutput a.mp4\nClick css:form button")
        }
    }

    @Test func webKitIsTheDefaultAndAChoiceIsKeptOrRefused() throws {
        #expect(try tape("Open https://a.dev\nOutput a.mp4").web.browser == .webkit)
        #expect(try tape("Open https://a.dev\nOutput a.mp4\nSet Browser chromium").web.browser == .chromium)
        #expect(try tape("Open https://a.dev\nOutput a.mp4\nSet Browser webkit").web.browser == .webkit)

        let found = URL(fileURLWithPath: "/Applications/Chromium.app")
        #expect(try BrowserChoice.webkit.resolve(locate: { found }) == .webkit, "WebKit even when Chromium is there")
        #expect(try BrowserChoice.chromium.resolve(locate: { found }) == .chromium(found))
        // A tape that chose a browser never gets another: no fall back to WebKit.
        #expect(throws: ReelError.self) { try BrowserChoice.chromium.resolve(locate: { nil }) }
        let brave = URL(fileURLWithPath: "/Applications/Brave Browser.app")
        #expect(throws: ReelError.self) { try BrowserChoice.app(brave).resolve(locate: { found }, exists: { _ in
            false
        }) }
        #expect(try BrowserChoice.app(brave).resolve(locate: { nil }, exists: { _ in true }) == .chromium(brave))
    }

    @Test func webKitKeysTypeWhatAppKitExpects() {
        #expect(WebKitPage.characters["return"] == "\r")
        #expect(WebKitPage.characters["delete"] == "\u{7F}")
        #expect(WebKitPage.characters["down"]?.unicodeScalars.first?.value == UInt32(NSDownArrowFunctionKey))
        #expect(WebKitPage.characters["f1"]?.unicodeScalars.first?.value == UInt32(NSF1FunctionKey))
    }
}

/// The drawn cursor, rendered over a plain grey take.
struct DrawnCursorTests {
    @Test func theCursorIsDrawnWhereTheTakeSaysItWas() async throws {
        let writer = TakeWriterTests()
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 2, audio: false, shade: 128)
        // 320×200 pixels at 2×: a 160×100 point page. The cursor rests at (20, 20) then jumps to (120, 60) at 1 s.
        var take = Take(width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 2000, events: [])
        take.cursor = [
            Take.Sample(ms: 0, frame: CGRect(x: 20, y: 20, width: 0, height: 0)),
            Take.Sample(ms: 1000, frame: CGRect(x: 120, y: 60, width: 0, height: 0)),
        ]
        take.drawnCursor = true
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Renderer.render(movie, take: take, overlays: [], soundtrack: .none, to: output)

        // The arrow's body, a little right of and below its tip, in pixels: 2 points across, 8 down, at 2×.
        let first = (x: 20 * 2 + 4, y: 20 * 2 + 16), second = (x: 120 * 2 + 4, y: 60 * 2 + 16)
        let early = try await shades(output.url, at: 0.5, [first, second])
        let late = try await shades(output.url, at: 1.5, [first, second])
        #expect(early[0] < 60 && abs(early[1] - late[0]) < 10, "at first the cursor is at the first point only")
        #expect(late[1] < 60 && late[0] > 100, "then at the second only (\(early), \(late))")
    }

    @Test func noCursorUnlessTheTakeAsks() async throws {
        let writer = TakeWriterTests()
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writer.writeTake(to: movie, seconds: 1, audio: false, shade: 128)
        var take = Take(width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 1000, events: [])
        take.cursor = [Take.Sample(ms: 0, frame: CGRect(x: 20, y: 20, width: 0, height: 0))]
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Renderer.render(movie, take: take, overlays: [], soundtrack: .none, to: output)
        #expect(
            try await shades(output.url, at: 0.5, [(x: 46, y: 54)])[0] > 100,
            "a native take's cursor is in the video"
        )
    }

    @Test func setCursorOffLeavesItOutWithoutANewTake() async throws {
        let writer = TakeWriterTests()
        let dir = try writer.temporaryDirectory()
        let location = TakeLocation(tape: dir.appending(path: "demo.reel"))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try await writer.writeTake(to: location.movie, seconds: 1, audio: false, shade: 128)
        var take = Take(
            width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 1000,
            events: [Take.Event(line: 3, command: "Sleep 1s", startMs: 0, endMs: 1000)]
        )
        take.cursor = [Take.Sample(ms: 0, frame: CGRect(x: 20, y: 20, width: 0, height: 0))]
        take.drawnCursor = true
        try location.write(take)
        // The same take rendered twice, the cursor on and then off: only the reel changed.
        for (setting, drawn) in [("on", true), ("off", false)] {
            let tape = try Tape.parse(
                "Open https://example.com\nOutput demo.mp4\nSet Cursor \(setting)\nSleep 1s", relativeTo: dir
            )
            try await Renderer.render(tape: tape, from: location, log: { _ in })
            let shade = try await shades(dir.appending(path: "demo.mp4"), at: 0.5, [(x: 44, y: 56)])[0]
            #expect(drawn ? shade < 60 : shade > 100, "Set Cursor \(setting): \(shade)")
        }
    }

    private func shades(_ url: URL, at time: Double, _ points: [(x: Int, y: Int)]) async throws -> [Int] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return points.map { point in
            let offset = (point.y * image.width + point.x) * 4
            return (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
        }
    }
}

struct BrowserLocatorTests {
    /// A made-up app: a bundle with an Info.plist naming it.
    private func app(_ path: URL, name: String, version: String) throws {
        let contents = path.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleName": name, "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
    }

    @Test func installedBrowsersComeBeforePlaywrightsNewestDownload() throws {
        let home = try TakeWriterTests().temporaryDirectory()
        let cache = home.appending(path: "Library/Caches/ms-playwright")
        try app(cache.appending(path: "chromium-1100/chrome-mac-arm64/Old.app"), name: "Old", version: "1")
        try app(cache.appending(path: "chromium-1234/chrome-mac-arm64/New.app"), name: "New", version: "151")
        try app(cache.appending(path: "chromium_headless_shell-9999/Shell.app"), name: "Shell", version: "9")

        let downloaded = try #require(Browser.locate(applications: [], home: home))
        #expect(downloaded.app.lastPathComponent == "New.app", "the newest build, not the headless shell")
        #expect(downloaded.source == .playwright("chromium-1234"))
        #expect(downloaded.description.hasPrefix("New 151 (Playwright's chromium-1234) at "))

        let installed = home.appending(path: "Applications/Brave Browser.app")
        try app(installed, name: "Brave Browser", version: "1.80")
        let found = try #require(Browser.locate(applications: ["/nowhere/Chrome.app", installed.path], home: home))
        // Compared by path: one URL knows it is a directory (a trailing slash), the other does not.
        #expect(found.app.path == installed.path && found.source == .installed)
    }

    @Test func aChosenBrowserIsUsedOrReported() throws {
        let home = try TakeWriterTests().temporaryDirectory()
        let chosen = home.appending(path: "Mine.app")
        try app(chosen, name: "Mine", version: "2")
        #expect(Browser.locate(chosen, applications: [], home: home)?.source == .chosen)
        #expect(Browser.locate(home.appending(path: "Gone.app"), applications: [], home: home) == nil)
        #expect(Browser.locate(applications: [], home: home) == nil, "nothing installed, nothing downloaded")
    }
}

struct WindowPlacementTests {
    @Test func aResizedWindowIsCentredOnItsDisplayBelowTheMenuBar() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(Recorder.centred(CGSize(width: 1440, height: 900), on: display) == CGPoint(x: 240, y: 90))
        // Taller than leaves room: below the menu bar, not under it.
        #expect(Recorder.centred(CGSize(width: 1000, height: 1060), on: display).y == 40)
        // A second display to the right: centred on that one.
        let right = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        #expect(Recorder.centred(CGSize(width: 1440, height: 900), on: right) == CGPoint(x: 2480, y: 270))
    }
}

/// WebKit's page as reel sets it up.
@MainActor
struct WebKitConfigurationTests {
    @Test func everyTakeStartsWithNothingKept() {
        let configuration = WebKitPage.configuration()
        #expect(!configuration.websiteDataStore.isPersistent)
        #expect(configuration.mediaTypesRequiringUserActionForPlayback == [])
    }
}

/// How reel starts Chromium.
struct ChromiumArgumentsTests {
    @Test func aFreshProfileThatNeverAsksForTheKeychain() {
        let arguments = Browser.arguments(
            profile: URL(fileURLWithPath: "/tmp/p"), viewport: CGSize(width: 1280, height: 720),
            url: URL(string: "https://example.com")!
        )
        #expect(arguments.contains("--use-mock-keychain"))
        #expect(arguments.contains("--user-data-dir=/tmp/p"))
        #expect(arguments.contains("--window-size=1280,748"))
        #expect(arguments.last == "--app=https://example.com")
    }
}

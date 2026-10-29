import AVFoundation
import CoreMedia
import Foundation
@testable import ReelCore
import Testing

private let dir = URL(fileURLWithPath: "/tmp/demos")

private func tape(_ text: String) throws -> Tape {
    try Tape.parse(text, relativeTo: dir)
}

struct WebParsingTests {
    @Test func aWebTape() throws {
        let parsed = try tape("""
        Output a.mp4
        Set Browser "/Applications/Brave Browser.app"
        Set Viewport 1000x700
        Open https://example.com/start
        Click "Sign in"
        Click css:form .submit
        Wait #email
        Open site/next.html
        """.replacingOccurrences(of: "css:form .submit", with: "css:.submit"))
        #expect(parsed.launch == .web(URL(string: "https://example.com/start")!))
        #expect(parsed.web.browser == URL(fileURLWithPath: "/Applications/Brave Browser.app"))
        #expect(parsed.web.viewport == CGSize(width: 1000, height: 700))
        #expect(parsed.steps.map(\.command) == [
            .click(.label("Sign in")), .click(.css(".submit")), .wait(.identifier("email")),
            .open(URL(fileURLWithPath: "/tmp/demos/site/next.html")),
        ])
        // A web tape needs no Accessibility: input goes to the page.
        #expect(parsed.launch.isWeb)
        #expect(try tape("Output a.mp4\nOpen file:///tmp/a.html").web == WebSettings())
    }

    @Test(arguments: [
        (
            "Output a.mp4\nOpen example.com",
            2,
            "'example.com' is not a web address; write https://…, http://…, file://… or a path to an .html file"
        ),
        (
            "Output a.mp4\nLaunch x\nOpen https://a.dev",
            3,
            "Open after the tape has started goes to another page, which needs a web tape"
        ),
        (
            "Output a.mp4\nOpen https://a.dev\nLaunch x",
            3,
            "a tape launches one app or opens one page; line 2 already does"
        ),
        ("Output a.mp4\nLaunch x\nClick css:.buy", 3, "css: targets are for web pages; Open one instead of Launch"),
        (
            "Output a.mp4\nSet Browser Chrome\nOpen https://a.dev",
            2,
            "Browser is a Chromium-based .app, such as /Applications/Brave Browser.app"
        ),
        (
            "Output a.mp4\nSet Viewport big\nOpen https://a.dev",
            2,
            "Viewport must be <width>x<height> in points, such as 1280x800, not 'big'"
        ),
        ("Output a.mp4\nOpen https://a.dev\nClick css:", 3, "css: needs a selector after it, such as css:.pricing"),
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

    @Test func aChosenBrowserMustExist() {
        #expect(throws: ReelError.self) { try Browser.find(URL(fileURLWithPath: "/nowhere/Browser.app")) }
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

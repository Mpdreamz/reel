import AVFoundation
import CoreMedia
import Foundation
@testable import ReelCore
import Testing

private func tape(_ body: String) throws -> Tape {
    try Tape.parse("Output a.mp4\nLaunch x\n" + body, relativeTo: URL(fileURLWithPath: "/tmp"))
}

/// A take of `tape`'s actions, each a second long, back to back from 0.
private func take(_ tape: Tape, events edit: ((inout [Take.Event]) -> Void)? = nil, width: Int = 1600) -> Take {
    var events = tape.actions.enumerated().map { index, step in
        Take.Event(line: step.line, command: step.source, startMs: index * 1000, endMs: index * 1000 + 1000)
    }
    edit?(&events)
    return Take(
        width: width, height: 1000, scale: 2, frameRate: 30, audio: true, durationMs: events.count * 1000,
        events: events
    )
}

struct CutParsingTests {
    @Test func zoomSpeedAndTrims() throws {
        let parsed = try tape("""
        Hide
        Sleep 1s
        Show
        Zoom #list
        Zoom "Library" 2.5x
        Zoom @100,50 2x
        Zoom cursor
        Zoom off
        Speed 4x
        Speed off
        """)
        #expect(parsed.steps.map(\.command) == [
            .hide(true), .sleep(.seconds(1)), .hide(false),
            .zoom(.element(.identifier("list")), scale: nil, transition: nil),
            .zoom(.element(.label("Library")), scale: 2.5, transition: nil),
            .zoom(.point(CGPoint(x: 100, y: 50)), scale: 2, transition: nil),
            .zoom(.cursor, scale: nil, transition: nil), .zoom(.off, scale: nil, transition: nil),
            .speed(4), .speed(nil),
        ])
        // Only a zoom on an element is recorded (and needs Accessibility); the rest is render's.
        #expect(parsed.actions.map(\.line) == [4, 6, 7])
        #expect(parsed.drivesTheApp)
        #expect(try !tape("Zoom @1,1\nSpeed 2x\nHide").drivesTheApp)
    }

    @Test func transitions() throws {
        let parsed = try tape("""
        Zoom@ease-out @1,1
        Zoom@600ms #list 2x
        Zoom@800ms,ease-in off
        Zoom cursor
        """)
        #expect(parsed.steps.map(\.command) == [
            .zoom(.point(CGPoint(x: 1, y: 1)), scale: nil, transition: Transition(easing: .easeOut, duration: nil)),
            .zoom(
                .element(.identifier("list")),
                scale: 2,
                transition: Transition(easing: nil, duration: .milliseconds(600))
            ),
            .zoom(.off, scale: nil, transition: Transition(easing: .easeIn, duration: .milliseconds(800))),
            .zoom(.cursor, scale: nil, transition: nil),
        ])
        // An element zoom's timeline names the element alone: its scale and easing change without a new take.
        #expect(parsed.steps[1].source == "Zoom #list")
        #expect(parsed.zoomTransition == .standard)
        let set = try tape("Set ZoomEasing smooth\nSet ZoomDuration 1.5s").zoomTransition
        #expect(set == Transition(easing: .smooth, duration: .milliseconds(1500)))
    }

    @Test(arguments: [
        ("Zoom", "expected Zoom <element or @x,y> [scale], Zoom cursor [scale] or Zoom off"),
        (
            "Zoom@bouncy off",
            "'@bouncy' is not a transition; write an easing, a duration or both, such as @ease-out,600ms"
        ),
        (
            "Zoom@1s,2s off",
            "'@1s,2s' is not a transition; write an easing, a duration or both, such as @ease-out,600ms"
        ),
        ("Speed@1s 2x", "Speed takes no @option"),
        ("Zoom off 2x", "Zoom off takes no scale"),
        ("Zoom #list 9x", "a zoom scale is 1x to 8x, such as 2x, not '9x'"),
        ("Zoom #list 2", "a zoom scale is 1x to 8x, such as 2x, not '2'"),
        ("Speed", "expected Speed <rate>x or Speed off"),
        ("Speed 1x", "Speed must be a rate above 1x and up to 16x, such as 4x, not '1x'"),
        ("Speed fast", "Speed must be a rate above 1x and up to 16x, such as 4x, not 'fast'"),
        ("Show", "nothing is hidden to Show"),
        ("Hide\nHide", "already hidden; Show comes first"),
        ("Hide now", "Hide takes nothing"),
    ])
    func errors(body: String, message: String) {
        let lines = body.split(separator: "\n").count
        #expect(throws: TapeError(line: 2 + lines, message: message)) { try tape(body) }
    }
}

struct EditTests {
    @Test func hiddenStretchesAreLeftOut() throws {
        let script = try tape("Sleep 1s\nHide\nSleep 1s\nShow\nSleep 1s")
        let edit = try Edit.make(tape: script, take: take(script))
        #expect(edit.segments == [.init(start: 0, end: 1, rate: 1), .init(start: 2, end: 3, rate: 1)])
        #expect(edit.duration == 2)
        #expect(edit.map(0.5) == 0.5)
        #expect(edit.map(1.5) == 1, "a hidden moment lands where the output picks up")
        #expect(edit.map(2.5) == 1.5)
    }

    @Test func spedUpStretchesPlayFaster() throws {
        let script = try tape("Sleep 1s\nSpeed 4x\nSleep 1s\nSleep 1s\nSpeed off\nSleep 1s")
        let edit = try Edit.make(tape: script, take: take(script))
        #expect(edit.segments == [
            .init(start: 0, end: 1, rate: 1), .init(start: 1, end: 3, rate: 4), .init(start: 3, end: 4, rate: 1),
        ])
        #expect(edit.duration == 2.5)
        #expect(edit.map(2) == 1.25)
        #expect(edit.map(3.5) == 2)
    }

    @Test func narrationKeepsItsOwnPace() throws {
        let script = try tape("Speed 2x\nSleep 1s\nSleep 1s\nSleep 1s")
        let edit = try Edit.make(tape: script, take: take(script), spoken: [1 ... 1.5])
        #expect(edit.segments == [
            .init(start: 0, end: 1, rate: 2), .init(start: 1, end: 1.5, rate: 1), .init(start: 1.5, end: 3, rate: 2),
        ])
        #expect(edit.map(1.25) == 0.75)
    }

    @Test func aHideMayNotCutNarration() throws {
        let script = try tape("Sleep 1s\nHide\nSleep 1s\nShow")
        #expect(throws: ReelError.self) { try Edit.make(tape: script, take: take(script), spoken: [1.5 ... 2.5]) }
    }

    @Test func aHideWithoutShowRunsToTheEnd() throws {
        let script = try tape("Sleep 1s\nHide\nSleep 1s")
        #expect(try Edit.make(tape: script, take: take(script)).duration == 1)
    }

    @Test func noEditIsTheWholeTake() throws {
        let script = try tape("Sleep 1s\nSleep 1s")
        #expect(try Edit.make(tape: script, take: take(script)).isIdentity)
    }
}

struct ZoomPlanTests {
    // The take's window is 800×500 points (1600×1000 pixels at 2×).

    @Test func aPointZoomsAroundItAndStaysInTheWindow() throws {
        let script = try tape("Sleep 1s\nZoom @400,250 2x\nSleep 1s\nZoom @10,10 2x\nSleep 1s")
        let plan = ZoomPlan.make(tape: script, take: take(script))
        #expect(plan.region(at: 0.5) == CGRect(x: 0, y: 0, width: 800, height: 500))
        #expect(plan.region(at: 1.5) == CGRect(x: 200, y: 125, width: 400, height: 250))
        // Near the corner it stops at the window's edge rather than show past it.
        #expect(plan.region(at: 2.5) == CGRect(x: 0, y: 0, width: 400, height: 250))
    }

    @Test func zoomsEaseInAndOut() throws {
        let script = try tape("Sleep 1s\nZoom @400,250 2x\nSleep 1s\nZoom off\nSleep 1s")
        let plan = ZoomPlan.make(tape: script, take: take(script))
        let halfway = plan.region(at: 1.2)
        #expect(abs(halfway.width - 600) < 1e-6, "halfway between 800 and 400 at the middle of the ease")
        #expect(abs(plan.region(at: 1.4).width - 400) < 1e-6)
        #expect(abs(plan.region(at: 2.4).width - 800) < 1e-6)
    }

    @Test func eachZoomCanEaseItsOwnWay() throws {
        let script = try tape("""
        Set ZoomEasing linear
        Set ZoomDuration 1s
        Sleep 1s
        Zoom @400,250 2x
        Sleep 2s
        Zoom@ease-in,500ms off
        Sleep 1s
        Zoom@snap @400,250 4x
        Sleep 1s
        """)
        let plan = ZoomPlan.make(tape: script, take: take(script))
        // The tape's linear second: a quarter of the way at 1.25 s, 800 to 400 wide.
        // Each move starts from where the zoom was a microsecond before it, hence the hundredth's slack.
        #expect(abs(plan.region(at: 1.25).width - 700) < 0.01)
        // Ease-in over half a second: an eighth of the way (cubic) at the halfway mark, 400 back to 800.
        #expect(abs(plan.region(at: 2.25).width - 450) < 0.01)
        #expect(abs(plan.region(at: 2.5).width - 800) < 0.01)
        // Snap: there at once.
        #expect(abs(plan.region(at: 3.001).width - 200) < 0.01)
    }

    @Test func anElementIsFittedWithRoomAndFollowed() throws {
        let script = try tape("Zoom #list\nSleep 1s\nSleep 1s")
        var recorded = take(script) {
            $0[0].x = 100
            $0[0].y = 100
            $0[0].w = 200
            $0[0].h = 100
        }
        // After the second step the list has moved 300 points right.
        recorded.focus = [Take.Sample(ms: 2000, frame: CGRect(x: 400, y: 100, width: 200, height: 100))]
        let plan = ZoomPlan.make(tape: script, take: recorded)
        let fitted = plan.region(at: 1.5)
        // 200×100 with 8% room is 232 wide: 800 / 232 ≈ 3.45×, of the window's shape.
        #expect(abs(fitted.width - 232) < 0.5)
        #expect(abs(fitted.width / fitted.height - 1.6) < 0.001)
        #expect(abs(fitted.midX - 200) < 0.5 && abs(fitted.midY - 150) < 0.5)
        #expect(abs(plan.region(at: 2.5).midX - 500) < 0.5, "locked on the list where it went")
    }

    @Test func aFittedElementAsWideAsTheWindowGetsANote() throws {
        let script = try tape("Zoom #list\nSleep 1s")
        let plan = ZoomPlan.make(tape: script, take: take(script) {
            $0[0].x = 10
            $0[0].y = 100
            $0[0].w = 780
            $0[0].h = 300
        })
        #expect(plan.notes == [
            "line 3: the element nearly fills the window, so fitting it barely zooms; give a scale, such as Zoom #list 2x",
        ])
    }

    @Test func aTinyElementIsNotZoomedPastTheFitLimit() throws {
        let script = try tape("Zoom #dot\nSleep 1s")
        let plan = ZoomPlan.make(tape: script, take: take(script) {
            $0[0].x = 400
            $0[0].y = 250
            $0[0].w = 4
            $0[0].h = 4
        })
        #expect(abs(plan.region(at: 0.9).width - 800 / ZoomPlan.fitLimit) < 1e-6)
    }

    @Test func theCursorIsFollowedSmoothly() throws {
        let script = try tape("Sleep 1s\nZoom cursor\nSleep 2s")
        var recorded = take(script)
        recorded.cursor = (0 ... 90).map { i in
            // Moving right 100 points a second, jittering 10 points either way.
            Take.Sample(
                ms: i * 33,
                frame: CGRect(x: 300 + Double(i) * 3.3 + (i % 2 == 0 ? 10 : -10), y: 250, width: 0, height: 0)
            )
        }
        let plan = ZoomPlan.make(tape: script, take: recorded)
        let a = plan.region(at: 1.6).midX, b = plan.region(at: 1.633).midX
        #expect(abs((b - a) - 3.3) < 2, "moves with the cursor, not with its jitter (\(b - a))")
    }

    @Test func overlaysMoveWithTheEditAndRipplesWithTheZoom() throws {
        let script = try tape("Sleep 1s\nZoom @200,125 2x\nSleep 1s\nSleep 1s")
        let plan = ZoomPlan.make(tape: script, take: take(script))
        let edit = Edit(segments: [.init(start: 0, end: 1, rate: 1), .init(start: 2, end: 3, rate: 1)])
        let mapped = OverlayPlan.mapped([
            Overlay(kind: .caption("early"), start: 0.2, end: 0.8),
            Overlay(kind: .caption("cut"), start: 1.2, end: 1.8),
            Overlay(kind: .ripple(CGPoint(x: 200, y: 125)), start: 2.5, end: 2.9),
        ], through: edit, zoom: plan)
        #expect(mapped == [
            Overlay(kind: .caption("early"), start: 0.2, end: 0.8),
            // The zoom frames 0…400 × 0…250 at 2×: the ripple's point lands in the middle of the frame.
            Overlay(kind: .ripple(CGPoint(x: 400, y: 250)), start: 1.5, end: 1.9),
        ])
    }

    @Test func pointsProjectThroughTheZoom() {
        let plan = ZoomPlan.full(CGSize(width: 800, height: 500))
        let projected = plan.project(CGPoint(x: 300, y: 200), through: CGRect(x: 200, y: 125, width: 400, height: 250))
        #expect(projected == CGPoint(x: 200, y: 150))
    }
}

/// Real renders of generated takes.
struct CutRenderTests {
    @Test func aZoomFillsTheFrameWithItsRegion() async throws {
        let dir = try TakeWriterTests().temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        try await writeQuadrants(to: movie, seconds: 2)
        // 320×200 pixels at 2× is a 160×100 point window; zoom the top right quadrant's centre, 2×. A region away
        // from the origin, so the transform's offset matters.
        let script = try tape("Sleep 1s\nZoom @120,25 2x\nSleep 1s")
        let recorded = Take(
            width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 2000,
            events: [
                Take.Event(line: 3, command: "Sleep 1s", startMs: 0, endMs: 500),
                Take.Event(line: 5, command: "Sleep 1s", startMs: 500, endMs: 2000),
            ]
        )
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Renderer.render(
            movie, take: recorded, overlays: [], soundtrack: .none,
            cut: .init(edit: .whole(2), zoom: ZoomPlan.make(tape: script, take: recorded)), to: output
        )
        let before = try await colours(output.url, at: 0.2)
        let after = try await colours(output.url, at: 1.5)
        #expect(before == ["red", "green", "blue", "white"], "the four quadrants before the zoom")
        #expect(after == ["green", "green", "green", "green"], "only the top right quadrant once zoomed")
    }

    @Test func hiddenAndSpedUpStretchesShortenTheMovie() async throws {
        let writer = TakeWriterTests()
        let dir = try writer.temporaryDirectory()
        let movie = dir.appending(path: "take.mov")
        // A fade from black to white over 3 s: a frame's shade says when in the take it is from.
        try await writer.writeTake(to: movie, seconds: 3, audio: false)
        let edit = Edit(segments: [
            .init(start: 0, end: 0.5, rate: 1), .init(start: 1, end: 2, rate: 2), .init(start: 2, end: 3, rate: 1),
        ])
        let recorded = Take(
            width: 320,
            height: 200,
            scale: 2,
            frameRate: 30,
            audio: false,
            durationMs: 3000,
            events: []
        )
        let output = Output(url: dir.appending(path: "out.mp4"), format: .mp4)
        try await Renderer.render(
            movie, take: recorded, overlays: [], soundtrack: .none, cut: .init(edit: edit), to: output
        )
        let asset = AVURLAsset(url: output.url)
        #expect(try await abs(asset.load(.duration).seconds - 2) < 0.06, "0.5 + 1 / 2 + 1 seconds")
        // 0.75 s into the output is 1.5 s into the take (sped up from 0.5 s); 1.5 s is 2.5 s.
        for (output, source) in [(0.25, 0.25), (0.75, 1.5), (1.5, 2.5)] {
            let shade = try await brightness(asset, at: output)
            let expected = source / 3 * 255
            #expect(
                abs(Double(shade) - expected) < 25,
                "at \(output) s the take's \(source) s (\(shade) vs \(expected))"
            )
        }
    }

    /// Four quadrants, red, green, blue and white, from the top left.
    private func writeQuadrants(to url: URL, seconds: Double) async throws {
        let writer = try TakeWriter(url: url, width: 320, height: 200, frameRate: 30, audio: false, realTime: false)
        await writer.perform {
            for i in 0 ..< Int(seconds * 30) {
                writer.append(video: quadrantFrame(at: CMTime(value: CMTimeValue(i), timescale: 30)))
            }
        }
        try await writer.finish(at: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    /// Names the colour at the centre of each quadrant, then of the frame's centre region in order: top left, top
    /// right, bottom left, bottom right.
    private func colours(_ url: URL, at time: Double) async throws -> [String] {
        let image = try await frame(AVURLAsset(url: url), at: time)
        return [(80, 50), (240, 50), (80, 150), (240, 150)].map { name(image.pixel($0.0, $0.1)) }
    }

    private func brightness(_ asset: AVAsset, at time: Double) async throws -> Int {
        let pixel = try await frame(asset, at: time).pixel(160, 100)
        return (pixel.0 + pixel.1 + pixel.2) / 3
    }

    private func name(_ pixel: (Int, Int, Int)) -> String {
        switch pixel {
        case let (r, g, b) where r > 180 && g > 180 && b > 180: "white"
        case let (r, g, b) where r > 150 && g < 90 && b < 90: "red"
        case let (r, g, b) where g > 150 && r < 90 && b < 90: "green"
        case let (r, g, b) where b > 150 && r < 90 && g < 90: "blue"
        default: "\(pixel)"
        }
    }

    private func frame(_ asset: AVAsset, at time: Double) async throws -> Bitmap {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        return try Bitmap(image)
    }
}

private struct Bitmap {
    let width: Int
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        self.bytes = bytes
    }

    func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}

/// A 320×200 BGRA frame of four quadrants: red, green, blue, white from the top left.
private func quadrantFrame(at time: CMTime) -> CMSampleBuffer {
    var pixels: CVPixelBuffer?
    CVPixelBufferCreate(
        nil, 320, 200, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels
    )
    let buffer = pixels!
    CVPixelBufferLockBaseAddress(buffer, [])
    let row = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    for y in 0 ..< 200 {
        for x in 0 ..< 320 {
            let (b, g, r): (UInt8, UInt8, UInt8) = switch (x < 160, y < 100) {
            case (true, true): (0, 0, 255)
            case (false, true): (0, 255, 0)
            case (true, false): (255, 0, 0)
            case (false, false): (255, 255, 255)
            }
            let p = base + y * row + x * 4
            (p[0], p[1], p[2], p[3]) = (b, g, r, 255)
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: time, decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
        allocator: nil, imageBuffer: buffer, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample
    )
    return sample!
}

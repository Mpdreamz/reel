import AppKit
import CoreMedia
import ScreenCaptureKit

/// Plays a tape against the real app and captures the take. Needs Screen Recording; nothing here runs in CI.
public enum Recorder {
    /// How long `Launch` waits for the app's first window.
    static let windowTimeout: Duration = .seconds(15)
    /// Lets a new window finish its opening animation before the first frame.
    static let settle: Duration = .milliseconds(500)
    static let firstFrameTimeout: Duration = .seconds(5)

    /// Records `tape` into `location`, on `channel` with any other reels running with it (`REEL_CHANNEL`, nil alone).
    public static func record(
        _ tape: Tape, into location: TakeLocation, channel: Channel? = Channel.fromEnvironment(),
        log: (String) -> Void
    ) async throws -> Take {
        guard !tape.launch.isSequence else {
            throw ReelError("a reel of scenes has no take of its own: Scenes.record records each scene")
        }
        if tape.drivesTheApp, !tape.launch.isWeb, !AXIsProcessTrusted() {
            throw ReelError(
                "this reel drives the app, which needs Accessibility for this terminal: System Settings → "
                    + "Privacy & Security → Accessibility, then run reel again"
            )
        }
        // Voiced before the app opens: a voice that cannot be reached fails here, not halfway through a take.
        let narration = try await Narration.prepare(
            tape, into: location.directory, voices: tape.voice.synthesizer(for:), log: log
        )
        switch tape.launch.screen {
        case .code:
            return try await recordScreen(tape, narration: narration, into: location, channel: channel, log: log)
        case .terminal:
            return try await recordTerminal(tape, narration: narration, into: location, channel: channel, log: log)
        case nil: break
        }
        let stage = if case let .web(url) = tape.launch {
            try await webStage(tape, opening: url, log: log)
        } else {
            try await appStage(tape, log: log)
        }
        defer { stage.close() }
        let (window, display, content, driver) = (stage.window, stage.display, stage.content, stage.driver)
        try await Task.sleep(for: settle)

        // The display without every other app, rather than `including: [app]`: scoped to the app, macOS draws a
        // sharing indicator over the window's buttons. Sound follows the same filter, so it is the app's alone (with
        // its helpers, where a browser plays a page's sound). Apps that start after this are not excluded; the crop
        // to the window keeps most of them out.
        let others = content.applications.filter { !stage.owns($0) }
        let filter = SCContentFilter(display: display, excludingApplications: others, exceptingWindows: [])
        let scale = Double(filter.pointPixelScale)
        // sourceRect is in the display's points; window frames are global. What is recorded is the stage's crop of
        // the window: all of it for an app, the page for a browser.
        let rect = stage.crop.offsetBy(
            dx: window.frame.minX - display.frame.minX, dy: window.frame.minY - display.frame.minY
        )
        let width = even(rect.width * scale), height = even(rect.height * scale)

        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(tape.frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        // A web page's cursor is drawn at render time: the real one never moves there.
        config.showsCursor = stage.web == nil
        config.queueDepth = 6
        config.capturesAudio = tape.audio
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true

        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let writer = try TakeWriter(
            url: location.movie, width: width, height: height, frameRate: tape.frameRate, audio: tape.audio
        )
        let sink = Sink(writer: writer)
        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: writer.queue)
        if tape.audio {
            try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: writer.queue)
        }

        log("recording \(window.owningApplication?.applicationName ?? "app"), \(width)×\(height)")
        try await stream.startCapture()
        let start: CMTime
        do {
            start = try await firstFrame(of: writer, sink: sink)
            var events: [Take.Event] = []
            var clock = SpeechClock()
            // The element a zoom is locked on: its frame is read again after every step, so render can follow it.
            var focus: Target?
            var focusTrack: [Take.Sample] = []
            let cursor = CursorSampler(window: window.frame.offsetBy(dx: stage.crop.minX, dy: stage.crop.minY))
            if stage.web == nil { cursor.start(at: start) }
            defer { cursor.stop() }
            stage.web?.clock = { milliseconds(since: start) }
            stage.web?.startTrack()
            let reel = location.reelName
            for step in tape.steps {
                // Any other zoom (a point, the cursor, off) releases the lock.
                if case let .zoom(target, _, _) = step.command, !target.isElement { focus = nil }
                guard !step.command.isRenderOnly else { continue }
                channel?.post(reel: reel, line: step.line, name: step.name, phase: .start)
                var begin = milliseconds(since: start)
                var landed: CGRect?
                var clip: String?
                switch step.command {
                case let .say(_, over):
                    guard let line = narration.lines[step.line]
                    else { throw ReelError("line \(step.line) was not voiced") }
                    let (spoken, resume) = clock.say(line, now: seconds(since: start), over: over)
                    try await sleep(until: resume, since: start)
                    begin = Int((spoken * 1000).rounded())
                    clip = line.key
                case let .reach(marker):
                    if let time = clock.time(of: marker) { try await sleep(until: time, since: start) }
                case let .waitFor(name, end):
                    do {
                        try await Channel.wait(
                            channel, for: name, end: end, timeout: tape.waitTimeout, line: step.line, log: log
                        )
                    } catch let error as ReelError {
                        throw ReelError("line \(step.line): \(error.description)")
                    }
                default:
                    landed = try await perform(step.command, with: driver)
                }
                if let error = sink.error { throw error }
                if case let .zoom(.element(target), _, _) = step.command { focus = target }
                events.append(Take.Event(
                    line: step.line, command: step.source, startMs: begin, endMs: milliseconds(since: start),
                    x: landed.map { Double($0.minX) }, y: landed.map { Double($0.minY) },
                    w: landed.flatMap { $0.isEmpty ? nil : Double($0.width) },
                    h: landed.flatMap { $0.isEmpty ? nil : Double($0.height) }, clip: clip
                ))
                channel?.post(reel: reel, line: step.line, name: step.name, phase: .end)
                if let focus, let frame = await driver?.currentFrame(of: focus) {
                    focusTrack.append(Take.Sample(ms: milliseconds(since: start), frame: frame))
                }
            }
            // The take runs until the last line has been said.
            try await sleep(until: clock.speechEnd, since: start)
            try await stream.stopCapture()
            let end = now()
            try await writer.finish(at: end)
            if writer.droppedFrames > 0 { log("dropped \(writer.droppedFrames) frames the encoder was not ready for") }

            var take = Take(
                width: width, height: height, scale: scale, frameRate: tape.frameRate, audio: tape.audio,
                durationMs: Int(((end - start).seconds * 1000).rounded()), events: events
            )
            take.cursor = stage.web?.track ?? cursor.stop()
            take.drawnCursor = stage.web != nil ? true : nil
            take.focus = focusTrack
            try location.write(take)
            return take
        } catch {
            try? await stream.stopCapture()
            throw error
        }
    }

    /// Without a driver the tape only sleeps (`drivesTheApp` is false).
    private static func perform(_ command: Command, with driver: (any Driving)?) async throws -> CGRect? {
        if let driver { return try await driver.perform(command) }
        if case let .sleep(duration) = command { try await Task.sleep(for: duration) }
        return nil
    }

    /// What a take records: a window, the part of it to keep, and how the tape's steps are played on it.
    struct Stage {
        var window: SCWindow
        var display: SCDisplay
        var content: SCShareableContent
        /// The part of the window recorded, in points from its top left.
        var crop: CGRect
        var driver: (any Driving)?
        var web: WebDriver?
        /// Whether a running app is part of what is recorded (its sound kept).
        var owns: (SCRunningApplication) -> Bool
        var close: () -> Void = {}
    }

    /// An app, launched and driven through Accessibility, its whole window recorded.
    private static func appStage(_ tape: Tape, log: (String) -> Void) async throws -> Stage {
        let pid = try await launch(tape.launch)
        log("waiting for a window of pid \(pid)")
        var (window, display, content) = try await firstWindow(of: pid)

        // Only a tape that drives the app needs Accessibility; one that only sleeps records without it.
        var driver: Driver?
        if tape.drivesTheApp {
            let found = try await accessibleDriver(pid: pid, window: window, tape: tape)
            found.activate()
            if let size = tape.size {
                try found.resize(to: size)
                // Centred on its display, below the menu bar: grown where it stood, a window can reach past the
                // display's edge, and what is past it records black. The same place every take, too.
                try found.move(to: centred(size, on: display.frame))
                try await Task.sleep(for: settle)
                (window, display, content) = try await firstWindow(of: pid, id: window.windowID)
                let actual = window.frame.size
                if abs(actual.width - size.width) > 1 || abs(actual.height - size.height) > 1 {
                    log(
                        "warning: the window is \(Int(actual.width))x\(Int(actual.height)), not "
                            + "\(Int(size.width))x\(Int(size.height)): the app limits its size, or a window manager "
                            + "(yabai, Rectangle) tiles it; let the app's windows float to record at Set Size"
                    )
                }
            }
            driver = found
        }
        return Stage(
            window: window, display: display, content: content, crop: CGRect(origin: .zero, size: window.frame.size),
            driver: driver, owns: { $0.processID == pid }
        )
    }

    /// Where a window of `size` sits centred on `display` (global points, top left), below the menu bar.
    static func centred(_ size: CGSize, on display: CGRect) -> CGPoint {
        let menuBar = 40.0
        let x = display.minX + max(0, (display.width - size.width) / 2)
        let y = display.minY + max(menuBar, (display.height - size.height) / 2)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// How long an app has, once its window is on screen, to show that window to Accessibility.
    static let accessibilityTimeout: Duration = .seconds(10)

    /// The driver for the app's window, once Accessibility sees it: an app's accessibility tree can come a moment
    /// after its window is on screen (a SwiftUI app builds it as it settles).
    private static func accessibleDriver(pid: pid_t, window: SCWindow, tape: Tape) async throws -> Driver {
        let deadline = ContinuousClock.now + accessibilityTimeout
        while true {
            do {
                return try Driver(pid: pid, windowFrame: window.frame, tape: tape)
            } catch {
                if ContinuousClock.now > deadline {
                    throw ReelError(
                        "the app's window did not show itself to Accessibility within \(accessibilityTimeout)"
                    )
                }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// A web page: in WebKit unless the tape chose a Chromium-based browser, which it then has to have. Only the page
    /// is recorded, below the window's title bar.
    private static func webStage(_ tape: Tape, opening url: URL, log: (String) -> Void) async throws -> Stage {
        switch try tape.web.browser.resolve(locate: { Browser.locate()?.app }) {
        case .webkit: try await webKitStage(tape, opening: url, log: log)
        case let .chromium(app): try await chromiumStage(tape, app: app, opening: url, log: log)
        }
    }

    /// WebKit, in a window of reel's own: the page's sound plays in WebKit's helper processes, so those are kept too.
    private static func webKitStage(_ tape: Tape, opening url: URL, log: (String) -> Void) async throws -> Stage {
        let page = try await WebKitPage.open(url, viewport: tape.web.viewport)
        log("opened \(url.absoluteString) in WebKit")
        let pid = ProcessInfo.processInfo.processIdentifier
        do {
            let (window, display, content) = try await firstWindow(of: pid)
            let viewport = await page.viewport()
            let driver = WebDriver(page: page, tape: tape, viewport: viewport)
            let crop = CGRect(
                x: 0, y: window.frame.height - viewport.height, width: viewport.width, height: viewport.height
            )
            return Stage(
                window: window, display: display, content: content, crop: crop, driver: driver, web: driver,
                owns: { $0.processID == pid || $0.bundleIdentifier.hasPrefix("com.apple.WebKit") },
                close: { Task { @MainActor in page.close() } }
            )
        } catch {
            await page.close()
            throw error
        }
    }

    /// A Chromium-based browser reel starts and drives over DevTools.
    private static func chromiumStage(
        _ tape: Tape, app: URL, opening url: URL, log: (String) -> Void
    ) async throws -> Stage {
        let browser = try await Browser.launch(app, viewport: tape.web.viewport, opening: url, log: log)
        do {
            let (window, display, content) = try await firstWindow(of: browser.pid)
            let viewport = try await browser.viewport()
            let driver = WebDriver(page: browser, tape: tape, viewport: viewport)
            // The page fills the window under its title bar.
            let crop = CGRect(
                x: 0, y: window.frame.height - viewport.height, width: viewport.width, height: viewport.height
            )
            let family = browser.bundleID
            return Stage(
                window: window, display: display, content: content, crop: crop, driver: driver, web: driver,
                owns: { $0.processID == browser.pid || $0.bundleIdentifier.hasPrefix(family) },
                close: { browser.close() }
            )
        } catch {
            browser.close()
            throw error
        }
    }

    private static func launch(_ target: LaunchTarget) async throws -> pid_t {
        let url: URL
        switch target {
        case let .bundleID(id):
            guard let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                let hint = id.hasSuffix(".app") ? "; for an app beside the reel, write ./\(id)" : ""
                throw ReelError("no app with bundle id \(id) is installed\(hint)")
            }
            url = found
        case let .app(path):
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw ReelError("no app at \(path.path)")
            }
            url = path
        case .web:
            preconditionFailure("a web page is opened by its stage")
        case .screen:
            preconditionFailure("a code screen is drawn, not launched")
        case .sequence:
            preconditionFailure("a reel of scenes records each scene's reel")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return app.processIdentifier
    }

    /// The largest normal window of `pid` (or the one with `id`) once it is on screen, the display it is on, and what
    /// else was running.
    private static func firstWindow(
        of pid: pid_t, id: CGWindowID? = nil
    ) async throws -> (SCWindow, SCDisplay, SCShareableContent) {
        let deadline = ContinuousClock.now + windowTimeout
        while true {
            let content = try await shareableContent()
            let windows = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.isOnScreen
                    && (id == nil || $0.windowID == id)
                    && $0.frame.width >= 50 && $0.frame.height >= 50
            }
            if let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
                let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
                guard let display = content.displays.first(where: { $0.frame.contains(center) }) else {
                    throw ReelError("the window is not on any display")
                }
                return (window, display, content)
            }
            if ContinuousClock.now > deadline {
                throw ReelError("the app showed no window within \(windowTimeout)")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw ReelError(
                "cannot list windows (\(error.localizedDescription)). Grant Screen Recording to this terminal: "
                    + "System Settings → Privacy & Security → Screen & System Audio Recording, then run reel again"
            )
        }
    }

    private static func firstFrame(of writer: TakeWriter, sink: Sink) async throws -> CMTime {
        let deadline = ContinuousClock.now + firstFrameTimeout
        while true {
            if let error = sink.error { throw error }
            if let time = writer.queue.sync(execute: { writer.firstFrameTime }) { return time }
            if ContinuousClock.now > deadline { throw ReelError("no frame arrived within \(firstFrameTimeout)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func now() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    private static func seconds(since start: CMTime) -> Double {
        (now() - start).seconds
    }

    private static func sleep(until time: Double, since start: CMTime) async throws {
        let left = time - seconds(since: start)
        if left > 0 { try await Task.sleep(for: .milliseconds(Int64(left * 1000))) }
    }

    private static func milliseconds(since start: CMTime) -> Int {
        Int(((now() - start).seconds * 1000).rounded())
    }

    static func even(_ pixels: CGFloat) -> Int {
        Int(pixels) & ~1
    }
}

/// Receives ScreenCaptureKit's buffers on the writer's queue and passes the complete frames on.
private final class Sink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let writer: TakeWriter
    private let lock = NSLock()
    private var failure: Error?

    init(writer: TakeWriter) {
        self.writer = writer
    }

    var error: Error? {
        lock.withLock { failure }
    }

    func stream(_: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid else { return }
        switch type {
        case .screen:
            // Idle frames (nothing changed) carry no image; the writer holds the last frame instead.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
                let raw = attachments.first?[.status] as? Int,
                SCFrameStatus(rawValue: raw) == .complete
            else { return }
            writer.append(video: buffer)
        case .audio:
            writer.append(audio: buffer)
        default:
            break
        }
    }

    func stream(_: SCStream, didStopWithError error: Error) {
        lock.withLock { failure = ReelError("capture stopped: \(error.localizedDescription)") }
    }
}

/// Where the cursor is, from the window's top left, about 30 times a second through the take: what `Zoom cursor`
/// follows at render time. Reads the event system's cursor, which needs no permission.
private final class CursorSampler: @unchecked Sendable {
    private let window: CGRect
    private let lock = NSLock()
    private var samples: [Take.Sample] = []
    private var task: Task<Void, Never>?

    init(window: CGRect) {
        self.window = window
    }

    func start(at start: CMTime) {
        task = Task.detached { [self] in
            while !Task.isCancelled {
                if let location = CGEvent(source: nil)?.location {
                    let ms = Int(((CMClockGetTime(CMClockGetHostTimeClock()) - start).seconds * 1000).rounded())
                    let point = CGRect(x: location.x - window.minX, y: location.y - window.minY, width: 0, height: 0)
                    lock.withLock { samples.append(Take.Sample(ms: ms, frame: point)) }
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    /// Stops sampling and hands over what was sampled.
    @discardableResult
    func stop() -> [Take.Sample] {
        task?.cancel()
        task = nil
        return lock.withLock { samples }
    }
}

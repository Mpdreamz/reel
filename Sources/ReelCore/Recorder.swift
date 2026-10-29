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

    public static func record(_ tape: Tape, into location: TakeLocation, log: (String) -> Void) async throws -> Take {
        if tape.drivesTheApp, !AXIsProcessTrusted() {
            throw ReelError(
                "this tape drives the app, which needs Accessibility for this terminal: System Settings → "
                    + "Privacy & Security → Accessibility, then run reel again"
            )
        }
        let pid = try await launch(tape.launch)
        log("waiting for a window of pid \(pid)")
        var (window, display, content) = try await firstWindow(of: pid)

        // Only a tape that drives the app needs Accessibility; one that only sleeps records without it.
        var driver: Driver?
        if tape.drivesTheApp {
            let found = try Driver(pid: pid, windowFrame: window.frame, tape: tape)
            found.activate()
            if let size = tape.size {
                try found.resize(to: size)
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
        try await Task.sleep(for: settle)

        // The display without every other app, rather than `including: [app]`: scoped to the app, macOS draws a
        // sharing indicator over the window's buttons. Sound follows the same filter, so it is the app's alone.
        // Apps that start after this are not excluded; the crop to the window keeps most of them out.
        let others = content.applications.filter { $0.processID != pid }
        let filter = SCContentFilter(display: display, excludingApplications: others, exceptingWindows: [])
        let scale = Double(filter.pointPixelScale)
        // sourceRect is in the display's points; window frames are global.
        let rect = window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let width = even(rect.width * scale), height = even(rect.height * scale)

        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(tape.frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
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
            for step in tape.actions {
                let begin = milliseconds(since: start)
                let point = try await perform(step.command, with: driver)
                if let error = sink.error { throw error }
                events.append(Take.Event(
                    line: step.line, command: step.source, startMs: begin, endMs: milliseconds(since: start),
                    x: point.map { Double($0.x) }, y: point.map { Double($0.y) }
                ))
            }
            try await stream.stopCapture()
            let end = now()
            try await writer.finish(at: end)
            if writer.droppedFrames > 0 { log("dropped \(writer.droppedFrames) frames the encoder was not ready for") }

            let take = Take(
                width: width, height: height, scale: scale, frameRate: tape.frameRate, audio: tape.audio,
                durationMs: Int(((end - start).seconds * 1000).rounded()), events: events
            )
            try location.write(take)
            return take
        } catch {
            try? await stream.stopCapture()
            throw error
        }
    }

    /// Without a driver the tape only sleeps (`drivesTheApp` is false).
    private static func perform(_ command: Command, with driver: Driver?) async throws -> CGPoint? {
        if let driver { return try await driver.perform(command) }
        if case let .sleep(duration) = command { try await Task.sleep(for: duration) }
        return nil
    }

    private static func launch(_ target: LaunchTarget) async throws -> pid_t {
        let url: URL
        switch target {
        case let .bundleID(id):
            guard let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                throw ReelError("no app with bundle id \(id) is installed")
            }
            url = found
        case let .app(path):
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw ReelError("no app at \(path.path)")
            }
            url = path
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

    private static func milliseconds(since start: CMTime) -> Int {
        Int(((now() - start).seconds * 1000).rounded())
    }

    private static func even(_ pixels: CGFloat) -> Int {
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

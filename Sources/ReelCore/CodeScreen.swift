import AppKit
import CoreMedia
import WebKit

/// reel's own editor: Monaco in a page that is never on screen, so a code screen needs no app, no window and no
/// permission. Nothing in the page keeps its own time: `pump` moves its clock on between frames, which is why the same
/// reel draws the same frames.
@MainActor
final class CodeScreen: NSObject, WKNavigationDelegate {
    /// The page, in points.
    let size: CGSize
    private let view: WKWebView
    private var loaded = false
    private var failed: String?

    static let loadTimeout: Duration = .seconds(20)

    /// The page and what it loads: `screen.html`, Monaco and the fonts, in the resource bundle SwiftPM builds beside
    /// reel. Found by hand rather than with `Bundle.module`, which stops the process when the bundle is missing.
    static func page() throws -> URL {
        let name = "Reel_ReelCore.bundle"
        let folders = [
            // Beside the binary, reached through the symlink Homebrew puts on the PATH.
            Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent(),
            // Beside whatever holds this code: the test bundle, when testing.
            Bundle(for: CodeScreen.self).bundleURL.deletingLastPathComponent(),
            Bundle.main.bundleURL,
        ]
        for folder in folders.compactMap(\.self) {
            for inside in ["Contents/Resources/Screen/screen.html", "Screen/screen.html"] {
                let page = folder.appending(path: name).appending(path: inside)
                if FileManager.default.fileExists(atPath: page.path) { return page }
            }
        }
        throw ReelError("reel's code screen is missing: no \(name) beside reel; reinstall reel")
    }

    init(size: CGSize, fontSize: Int) async throws {
        self.size = size
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        super.init()
        view.navigationDelegate = self
        let page = try Self.page()
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        let deadline = ContinuousClock.now + Self.loadTimeout
        while !loaded {
            if let failed { throw ReelError("the code screen did not load: \(failed)") }
            if ContinuousClock.now > deadline { throw ReelError("the code screen did not load in \(Self.loadTimeout)") }
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try await call("return reelScreen.init({fontSize: f})", ["f": fontSize])
        while true {
            if let error = try await call("return reelScreen.error") as? String {
                throw ReelError("the code screen did not start: \(error)")
            }
            if try await call("return reelScreen.ready") as? Bool == true { break }
            if ContinuousClock
                .now > deadline { throw ReelError("the code screen did not start in \(Self.loadTimeout)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    nonisolated func webView(_: WKWebView, didFinish _: WKNavigation!) {
        MainActor.assumeIsolated { loaded = true }
    }

    nonisolated func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated { failed = error.localizedDescription }
    }

    nonisolated func webView(
        _: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error
    ) {
        MainActor.assumeIsolated { failed = error.localizedDescription }
    }

    /// Runs `body` as an async function of `arguments`, which arrive as values (no quoting), and returns its result.
    @discardableResult
    func call(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        do {
            let value = try await view.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page)
            return value is NSNull ? nil : value
        } catch {
            let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
            throw ReelError("the code screen threw: \(message ?? error.localizedDescription)")
        }
    }

    /// Runs one of the page's steps, which answer with a problem (`"func play" is not in Player.swift`) or nothing.
    func step(_ body: String, _ arguments: [String: Any] = [:]) async throws {
        if let problem = try await call(body, arguments) as? String { throw ReelError(problem) }
    }

    /// Moves the page's clock on and lays the frame out. Returns whether anything may have moved since the last pump,
    /// and where the caret is (points from the page's top left).
    func pump(_ milliseconds: Int) async throws -> (changed: Bool, caret: CGPoint?) {
        let result = try await call("return reelScreen.pump(ms)", ["ms": milliseconds]) as? [String: Any]
        let changed = result?["changed"] as? Bool ?? true
        guard let x = result?["x"] as? Double, let y = result?["y"] as? Double else { return (changed, nil) }
        return (changed, CGPoint(x: x, y: y))
    }

    /// The page as it is now, `scale` pixels a point.
    func snapshot(scale: Double) async throws -> CGImage {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        configuration.snapshotWidth = NSNumber(value: Double(size.width))
        let image = try await view.takeSnapshot(configuration: configuration)
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ReelError("the code screen gave no picture")
        }
        if cg.width == width, cg.height == height { return cg }
        // The view drew at its display's scale; the take is at `scale`.
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw ReelError("cannot draw the code screen") }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw ReelError("cannot draw the code screen") }
        return scaled
    }
}

/// Turns pictures into frames a `TakeWriter` takes.
struct FrameMaker {
    let width: Int
    let height: Int
    private let format: CMVideoFormatDescription
    private let pool: CVPixelBufferPool

    init(width: Int, height: Int) throws {
        self.width = width
        self.height = height
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        guard let pool else { throw ReelError("cannot make frames of \(width)×\(height)") }
        self.pool = pool
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        var format: CMVideoFormatDescription?
        if let buffer { CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: buffer,
            formatDescriptionOut: &format
        ) }
        guard let format else { throw ReelError("cannot make frames of \(width)×\(height)") }
        self.format = format
    }

    func frame(_ image: CGImage, at milliseconds: Int, frameRate: Int) throws -> CMSampleBuffer {
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { throw ReelError("cannot make a frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw ReelError("cannot make a frame") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(frameRate)),
            presentationTimeStamp: CMTime(value: CMTimeValue(milliseconds), timescale: 1000),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: format, sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        guard let sample else { throw ReelError("cannot make a frame") }
        return sample
    }
}

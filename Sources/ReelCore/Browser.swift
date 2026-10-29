import AppKit
import Foundation

/// A Chromium-based browser reel started for one take: an app window (no tabs, no address bar) on a fresh profile,
/// driven over DevTools, its page sized to the tape's viewport. `close` quits it and removes the profile.
final class Browser: @unchecked Sendable {
    let process: Process
    let pid: pid_t
    /// The browser's bundle id: its helper processes, which play the page's sound, share it as a prefix.
    let bundleID: String
    let page: DevTools
    private let browser: DevTools
    private let profile: URL

    /// Where reel looks when the tape names no browser.
    static let candidates = [
        "/Applications/Google Chrome.app", "/Applications/Chromium.app", "/Applications/Brave Browser.app",
        "/Applications/Microsoft Edge.app",
    ]

    /// The tape's browser, else the first Chromium-based one installed, else Playwright's newest download.
    static func find(_ chosen: URL?) throws -> URL {
        if let chosen {
            guard FileManager.default.fileExists(atPath: chosen.path)
            else { throw ReelError("no browser at \(chosen.path)") }
            return chosen
        }
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }
        let cache = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches/ms-playwright")
        let builds = (try? FileManager.default.contentsOfDirectory(atPath: cache.path))?
            .filter { $0.hasPrefix("chromium-") }
            .sorted { (Int($0.dropFirst(9)) ?? 0) < (Int($1.dropFirst(9)) ?? 0) } ?? []
        for build in builds.reversed() {
            let directory = cache.appending(path: build)
            let apps = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [
                .skipsPackageDescendants,
            ])?.compactMap { $0 as? URL }.filter { $0.pathExtension == "app" } ?? []
            if let app = apps.first { return app }
        }
        throw ReelError(
            "no Chromium-based browser found (Chrome, Chromium, Brave, Edge or Playwright's); "
                + "install one, or Set Browser /path/to/Browser.app"
        )
    }

    static func launch(_ app: URL, viewport: CGSize, opening url: URL, log: (String) -> Void) async throws -> Browser {
        guard let bundle = Bundle(url: app), let executable = bundle.executableURL,
              let bundleID = bundle.bundleIdentifier
        else { throw ReelError("\(app.path) is not an app") }
        let profile = FileManager.default.temporaryDirectory.appending(path: "reel-browser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        // Sized close to the viewport (a title bar more), corrected once DevTools can measure the page.
        process.arguments = [
            "--user-data-dir=\(profile.path)", "--remote-debugging-port=0", "--remote-allow-origins=*",
            "--no-first-run", "--no-default-browser-check", "--disable-sync", "--hide-crash-restore-bubble",
            "--autoplay-policy=no-user-gesture-required", "--window-position=80,80",
            "--window-size=\(Int(viewport.width)),\(Int(viewport.height) + 28)", "--app=\(url.absoluteString)",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        log("opened \(url.absoluteString) in \(app.deletingPathExtension().lastPathComponent)")

        do {
            let port = try await devToolsPort(in: profile)
            let base = URL(string: "http://127.0.0.1:\(port)")!
            let version = try await json(base.appending(path: "json/version")) as? [String: Any]
            guard let browserSocket = (version?["webSocketDebuggerUrl"] as? String).flatMap(URL.init(string:)) else {
                throw ReelError("the browser gave no DevTools address")
            }
            let (pageID, pageSocket) = try await firstPage(at: base)
            let browser = Browser(
                process: process, bundleID: bundleID, page: DevTools(pageSocket), browser: DevTools(browserSocket),
                profile: profile
            )
            try await browser.waitForLoad()
            try await browser.size(to: viewport, target: pageID)
            return browser
        } catch {
            process.terminate()
            try? FileManager.default.removeItem(at: profile)
            throw error
        }
    }

    private init(process: Process, bundleID: String, page: DevTools, browser: DevTools, profile: URL) {
        self.process = process
        pid = process.processIdentifier
        self.bundleID = bundleID
        self.page = page
        self.browser = browser
        self.profile = profile
    }

    /// Goes to `url` and waits until the new page has loaded.
    func navigate(to url: URL) async throws {
        _ = try await page.evaluate("window.__reelLeaving = true")
        try await page.send("Page.navigate", ["url": url.absoluteString])
        try await waitForLoad(leaving: true)
    }

    /// Until the document is complete (and, after navigating, is a new one).
    func waitForLoad(leaving: Bool = false) async throws {
        let deadline = Date().addingTimeInterval(DevTools.timeout)
        let check = leaving ? "!window.__reelLeaving && document.readyState === 'complete'"
            : "document.readyState === 'complete'"
        while Date() < deadline {
            if await (try? page.evaluate(check)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ReelError("the page did not finish loading in \(Int(DevTools.timeout)) s")
    }

    /// Resizes the window until the page itself is `viewport`: what shows of it is what is recorded.
    private func size(to viewport: CGSize, target: String) async throws {
        let window = try await browser.send("Browser.getWindowForTarget", ["targetId": target])
        guard let id = window["windowId"] as? Int else { throw ReelError("the browser gave no window") }
        for _ in 0 ..< 4 {
            let inner = try await page.evaluate("[window.innerWidth, window.innerHeight]") as? [Double] ?? []
            guard inner.count == 2 else { break }
            let (dx, dy) = (viewport.width - inner[0], viewport.height - inner[1])
            if abs(dx) < 1, abs(dy) < 1 { return }
            let bounds = try await browser.send("Browser.getWindowBounds", ["windowId": id])["bounds"] as? [String: Any]
            let width = (bounds?["width"] as? Double ?? viewport.width) + dx
            let height = (bounds?["height"] as? Double ?? viewport.height) + dy
            try await browser.send("Browser.setWindowBounds", [
                "windowId": id, "bounds": ["width": Int(width), "height": Int(height), "windowState": "normal"],
            ])
            try await Task.sleep(for: .milliseconds(250))
        }
        let inner = try await page.evaluate("[window.innerWidth, window.innerHeight]") as? [Double] ?? []
        throw ReelError(
            "the page is \(inner.map { String(Int($0)) }.joined(separator: "x")), not "
                + "\(Int(viewport.width))x\(Int(viewport.height)): the screen may be too small, or a window manager "
                + "(yabai, Rectangle) tiles the browser; let it float to record at Set Viewport"
        )
    }

    /// The page's size as it is now, in points.
    func viewport() async throws -> CGSize {
        let inner = try await page.evaluate("[window.innerWidth, window.innerHeight]") as? [Double] ?? []
        guard inner.count == 2 else { throw ReelError("the page has no size") }
        return CGSize(width: inner[0], height: inner[1])
    }

    func close() {
        page.close()
        browser.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: profile)
    }

    private static func devToolsPort(in profile: URL) async throws -> Int {
        let file = profile.appending(path: "DevToolsActivePort")
        for _ in 0 ..< 150 {
            if let text = try? String(contentsOf: file, encoding: .utf8),
               let port = text.split(separator: "\n").first.flatMap({ Int($0) })
            {
                return port
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ReelError("the browser did not open DevTools within 15 s")
    }

    private static func firstPage(at base: URL) async throws -> (String, URL) {
        for _ in 0 ..< 50 {
            let targets = try await json(base.appending(path: "json/list")) as? [[String: Any]] ?? []
            if let page = targets.first(where: { $0["type"] as? String == "page" }),
               let id = page["id"] as? String,
               let socket = (page["webSocketDebuggerUrl"] as? String).flatMap(URL.init(string:))
            {
                return (id, socket)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ReelError("the browser opened no page")
    }

    private static func json(_ url: URL) async throws -> Any {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONSerialization.jsonObject(with: data)
    }
}

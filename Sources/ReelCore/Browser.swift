import AppKit
import Foundation

/// A Chromium-based browser reel started for one take: an app window (no tabs, no address bar) on a fresh profile,
/// driven over DevTools, its page sized to the tape's viewport. `close` quits it and removes the profile.
public final class Browser: @unchecked Sendable {
    let process: Process
    let pid: pid_t
    /// The browser's bundle id: its helper processes, which play the page's sound, share it as a prefix.
    let bundleID: String
    let page: DevTools
    private let browser: DevTools
    private let profile: URL

    /// Where reel looks when the tape names no browser, in order, before Playwright's downloads.
    public static let candidates = [
        "/Applications/Google Chrome.app", "/Applications/Chromium.app", "/Applications/Brave Browser.app",
        "/Applications/Microsoft Edge.app",
    ]

    /// A browser reel found, and where it found it.
    public struct Located: Equatable, Sendable {
        public enum Source: Equatable, Sendable {
            /// `Set Browser`.
            case chosen
            /// One of `candidates`.
            case installed
            /// Playwright's download, by its build directory (`chromium-1234`).
            case playwright(String)
        }

        public var app: URL
        public var source: Source

        /// The app's name and version, as its Info.plist has them.
        public var description: String {
            let info = Bundle(url: app)?.infoDictionary
            let name = info?["CFBundleName"] as? String ?? app.deletingPathExtension().lastPathComponent
            let version = (info?["CFBundleShortVersionString"] as? String).map { " \($0)" } ?? ""
            let from = switch source {
            case .chosen: "Set Browser"
            case .installed: "installed"
            case let .playwright(build): "Playwright's \(build)"
            }
            return "\(name)\(version) (\(from)) at \(app.path)"
        }
    }

    /// The tape's browser, else the first Chromium-based one installed, else Playwright's newest download; nil when
    /// there is none. `applications` and `home` are where to look, for tests.
    public static func locate(
        _ chosen: URL? = nil, applications: [String] = candidates,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Located? {
        let files = FileManager.default
        if let chosen { return files.fileExists(atPath: chosen.path) ? Located(app: chosen, source: .chosen) : nil }
        if let found = applications.first(where: { files.fileExists(atPath: $0) }) {
            return Located(app: URL(fileURLWithPath: found), source: .installed)
        }
        let cache = home.appending(path: "Library/Caches/ms-playwright")
        // `chromium-<build>`, newest first; `chromium_headless_shell-…` has no window to record.
        let builds = ((try? files.contentsOfDirectory(atPath: cache.path)) ?? [])
            .filter { $0.hasPrefix("chromium-") && Int($0.dropFirst(9)) != nil }
            .sorted { Int($0.dropFirst(9))! > Int($1.dropFirst(9))! }
        for build in builds {
            let apps = files.enumerator(
                at: cache.appending(path: build), includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]
            )?.compactMap { $0 as? URL }.filter { $0.pathExtension == "app" } ?? []
            if let app = apps.first { return Located(app: app, source: .playwright(build)) }
        }
        return nil
    }

    /// What Chromium is started with: a fresh profile, a DevTools port, an app window sized close to the viewport (a
    /// title bar more, corrected once DevTools can measure the page), and nothing that asks the user anything.
    static func arguments(profile: URL, viewport: CGSize, url: URL) -> [String] {
        [
            "--user-data-dir=\(profile.path)", "--remote-debugging-port=0", "--remote-allow-origins=*",
            "--no-first-run", "--no-default-browser-check", "--disable-sync", "--hide-crash-restore-bubble",
            "--autoplay-policy=no-user-gesture-required", "--window-position=80,80",
            // A fresh profile otherwise asks the login keychain for "Chromium Safe Storage", with a password dialog
            // left on screen every take.
            "--use-mock-keychain",
            "--window-size=\(Int(viewport.width)),\(Int(viewport.height) + 28)", "--app=\(url.absoluteString)",
        ]
    }

    static func launch(_ app: URL, viewport: CGSize, opening url: URL, log: (String) -> Void) async throws -> Browser {
        guard let bundle = Bundle(url: app), let executable = bundle.executableURL,
              let bundleID = bundle.bundleIdentifier
        else { throw ReelError("\(app.path) is not an app") }
        let profile = FileManager.default.temporaryDirectory.appending(path: "reel-browser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments(profile: profile, viewport: viewport, url: url)
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

    /// Loads the page again and waits until it has.
    func reload() async throws {
        _ = try await page.evaluate("window.__reelLeaving = true")
        try await page.send("Page.reload")
        try await waitForLoad(leaving: true)
    }

    /// Where the page is now.
    func location() async throws -> URL? {
        try await (page.evaluate("location.href") as? String).flatMap(URL.init(string:))
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
            // The page takes the new size a moment later, sometimes after 250 ms: wait for it, up to a second.
            for _ in 0 ..< 20 {
                try await Task.sleep(for: .milliseconds(50))
                let now = try await page.evaluate("[window.innerWidth, window.innerHeight]") as? [Double] ?? []
                if now != inner { break }
            }
        }
        // The last resize is checked too, not only those before it.
        let inner = try await page.evaluate("[window.innerWidth, window.innerHeight]") as? [Double] ?? []
        if inner.count == 2, abs(viewport.width - inner[0]) < 1, abs(viewport.height - inner[1]) < 1 { return }
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
        throw ReelError("the browser did not open DevTools within 15 s: is it Chromium-based?")
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

/// A Chromium page, driven over DevTools.
extension Browser: Page {
    func numbers(_ script: String) async throws -> [Double]? {
        try await page.evaluate(script) as? [Double]
    }

    func mouse(_ action: MouseAction, at point: CGPoint) async throws {
        var event: [String: Any] = ["x": point.x, "y": point.y]
        switch action {
        case .move: event["type"] = "mouseMoved"
        case .down, .up:
            event["type"] = action == .down ? "mousePressed" : "mouseReleased"
            event["button"] = "left"
            event["clickCount"] = 1
        }
        try await page.send("Input.dispatchMouseEvent", event)
    }

    func wheel(dx: Double, dy: Double, at point: CGPoint) async throws {
        try await page.send("Input.dispatchMouseEvent", [
            "type": "mouseWheel", "x": point.x, "y": point.y, "deltaX": dx, "deltaY": dy,
        ])
    }

    func type(_ text: String) async throws {
        try await page.send(
            "Input.dispatchKeyEvent",
            ["type": "keyDown", "text": text, "key": text, "unmodifiedText": text]
        )
        try await page.send("Input.dispatchKeyEvent", ["type": "keyUp", "key": text])
    }

    func key(_ combo: KeyCombo) async throws {
        let key = WebDriver.keys[combo.key] ?? WebDriver.WebKey(
            key: combo.key, code: "Key\(combo.key.uppercased())",
            keyCode: Int(combo.key.uppercased().unicodeScalars.first!.value)
        )
        var modifiers = 0
        if combo.modifiers.contains(.option) { modifiers |= 1 }
        if combo.modifiers.contains(.control) { modifiers |= 2 }
        if combo.modifiers.contains(.command) { modifiers |= 4 }
        if combo.modifiers.contains(.shift) { modifiers |= 8 }
        var down: [String: Any] = [
            "type": "keyDown", "key": key.key, "code": key.code, "windowsVirtualKeyCode": key.keyCode,
            "modifiers": modifiers,
        ]
        // Text only for keys that type, unmodified (or shifted).
        if let text = key.text, modifiers & ~8 == 0 { down["text"] = text }
        // On macOS the page's editing shortcuts are commands, not key presses: DevTools has to name them.
        if let command = WebDriver.commands[combo.description] { down["commands"] = [command] }
        try await page.send("Input.dispatchKeyEvent", down)
        try await Task.sleep(for: WebDriver.press)
        try await page.send("Input.dispatchKeyEvent", [
            "type": "keyUp", "key": key.key, "code": key.code, "windowsVirtualKeyCode": key.keyCode,
            "modifiers": modifiers,
        ])
    }
}

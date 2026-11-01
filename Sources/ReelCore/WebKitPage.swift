import AppKit
import WebKit

/// A web page in WebKit, built into macOS: a view in a window of reel's own. Input is AppKit events sent straight into
/// that window, so the page sees trusted clicks and keys, and the screen's mouse and keyboard stay the user's.
@MainActor
final class WebKitPage: Page {
    let window: NSWindow
    let view: WKWebView
    private var events = 0

    /// The page's setup: sound plays without a click, and nothing is kept between takes (cookies, storage, cache),
    /// as with Chromium's fresh profile, so a reel records the same way every time: a page that asks for cookie
    /// consent asks every take.
    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }

    /// Opens `url` in a new window whose page is `viewport`, and waits for it to load.
    static func open(_ url: URL, viewport: CGSize) async throws -> WebKitPage {
        // reel is a command line tool: it becomes an app (with a Dock icon) for as long as its window is up.
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let view = WKWebView(frame: CGRect(origin: .zero, size: viewport), configuration: configuration())
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: viewport), styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = url.lastPathComponent.isEmpty ? (url.host() ?? "reel") : url.lastPathComponent
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.contentView = view
        if let screen = NSScreen.main?.visibleFrame {
            window.setFrameTopLeftPoint(CGPoint(x: screen.minX + 80, y: screen.maxY - 80))
        }
        window.makeKeyAndOrderFront(nil)
        app.activate()
        window.makeFirstResponder(view)
        let page = WebKitPage(window: window, view: view)
        try await page.load(url)
        return page
    }

    private init(window: NSWindow, view: WKWebView) {
        self.window = window
        self.view = view
    }

    func numbers(_ script: String) async throws -> [Double]? {
        try await evaluate(script) as? [Double]
    }

    private func evaluate(_ script: String) async throws -> Any? {
        do {
            let value = try await view.callAsyncJavaScript("return \(script)", contentWorld: .page)
            return value is NSNull ? nil : value
        } catch {
            throw ReelError("the page threw: \(error.localizedDescription)")
        }
    }

    func mouse(_ action: MouseAction, at point: CGPoint) async throws {
        let type: NSEvent.EventType = switch action {
        case .move: .mouseMoved
        case .down: .leftMouseDown
        case .up: .leftMouseUp
        }
        events += 1
        guard let event = NSEvent.mouseEvent(
            with: type, location: windowPoint(point), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: events, clickCount: action == .move ? 0 : 1,
            pressure: action == .down ? 1 : 0
        ) else { throw ReelError("cannot make a mouse event") }
        // Straight to the view under the point: through the window, a click on a window that is not key only makes
        // it key, and moves are only tracked for the key window.
        let target = hit(point)
        switch action {
        case .move: target.mouseMoved(with: event)
        case .down: target.mouseDown(with: event)
        case .up: target.mouseUp(with: event)
        }
    }

    /// The view the page's point falls on, in the window: WebKit's own view inside the web view.
    private func hit(_ point: CGPoint) -> NSView {
        let inWindow = windowPoint(point)
        return window.contentView?.hitTest(window.contentView!.convert(inWindow, from: nil)) ?? view
    }

    /// Scrolls what is under the point. WebKit takes wheel events (and mouse moves) only while its app is active,
    /// which reel, started from a terminal, cannot make itself: so the page scrolls its own nearest scrollable element
    /// under the point, firing its usual scroll events. A page listening for wheel events themselves does not see them.
    func wheel(dx: Double, dy: Double, at point: CGPoint) async throws {
        _ = try await evaluate("""
        ((x, y, dx, dy) => {
          const scrolls = (e, axis) => { const s = getComputedStyle(e)[axis === 'y' ? 'overflowY' : 'overflowX'];
            return /(auto|scroll)/.test(s) && (axis === 'y' ? e.scrollHeight > e.clientHeight : e.scrollWidth > e.clientWidth); };
          let e = document.elementFromPoint(x, y);
          while (e && !(dy && scrolls(e, 'y')) && !(dx && scrolls(e, 'x'))) e = e.parentElement;
          (e || document.scrollingElement).scrollBy({left: dx, top: dy, behavior: 'instant'});
          return null;
        })(\(point.x), \(point.y), \(dx), \(dy))
        """)
    }

    func type(_ text: String) async throws {
        try send(text, keyCode: 0, modifiers: [])
    }

    func key(_ combo: KeyCombo) async throws {
        // Editing shortcuts are actions on the page, as its Edit menu would send them.
        // Sent to the window's own first responder (the web view): with no target an action goes to the key window,
        // which reel's window need not be.
        if let command = WebDriver.commands[combo.description] {
            let action = Selector("\(command):")
            guard let responder = window.firstResponder, responder.tryToPerform(action, with: nil) else {
                throw ReelError("the page did not take \(combo.description) (\(command))")
            }
            return
        }
        var flags: NSEvent.ModifierFlags = []
        if combo.modifiers.contains(.command) { flags.insert(.command) }
        if combo.modifiers.contains(.shift) { flags.insert(.shift) }
        if combo.modifiers.contains(.option) { flags.insert(.option) }
        if combo.modifiers.contains(.control) { flags.insert(.control) }
        if combo.modifiers.contains(.function) { flags.insert(.function) }
        try send(Self.characters[combo.key] ?? combo.key, keyCode: combo.keyCode, modifiers: flags)
    }

    func navigate(to url: URL) async throws {
        try await load(url)
    }

    func reload() async throws {
        _ = try? await evaluate("window.__reelLeaving = true")
        view.reload()
        try await waitForLoad()
    }

    func location() async throws -> URL? {
        try await (evaluate("location.href") as? String).flatMap(URL.init(string:))
    }

    func close() {
        view.stopLoading()
        window.close()
    }

    /// The page's size as it is now, in points.
    func viewport() -> CGSize {
        view.bounds.size
    }

    private func load(_ url: URL) async throws {
        _ = try? await evaluate("window.__reelLeaving = true")
        if url.isFileURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.load(URLRequest(url: url))
        }
        try await waitForLoad()
    }

    /// Until a new document, one that has not been told it is leaving, is complete.
    private func waitForLoad() async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let ready = try? await evaluate("!window.__reelLeaving && document.readyState === 'complete'")
            if ready as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ReelError("the page did not finish loading in 15 s")
    }

    /// A key down and up, as the keyboard would send them.
    private func send(_ characters: String, keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            events += 1
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ) else { throw ReelError("cannot make a key event") }
            window.sendEvent(event)
        }
    }

    /// A point of the page in the window's coordinates (y up, from the bottom).
    private func windowPoint(_ point: CGPoint) -> CGPoint {
        let local = view.isFlipped ? point : CGPoint(x: point.x, y: view.bounds.height - point.y)
        return view.convert(local, to: nil)
    }

    /// What named keys type, as AppKit has them.
    nonisolated static let characters: [String: String] = {
        func key(_ code: Int) -> String {
            String(UnicodeScalar(UInt16(code)).map(Character.init) ?? " ")
        }
        var characters = [
            "return": "\r", "enter": "\r", "tab": "\t", "space": " ", "delete": "\u{7F}", "backspace": "\u{7F}",
            "escape": "\u{1B}", "esc": "\u{1B}",
            "forwarddelete": key(NSDeleteFunctionKey), "home": key(NSHomeFunctionKey), "end": key(NSEndFunctionKey),
            "pageup": key(NSPageUpFunctionKey), "pagedown": key(NSPageDownFunctionKey),
            "left": key(NSLeftArrowFunctionKey), "right": key(NSRightArrowFunctionKey), "up": key(NSUpArrowFunctionKey),
            "down": key(NSDownArrowFunctionKey),
        ]
        for n in 1 ... 12 {
            characters["f\(n)"] = key(NSF1FunctionKey + n - 1)
        }
        return characters
    }()
}

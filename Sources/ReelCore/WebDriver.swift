import CoreGraphics
import Foundation

/// A web page reel drives: in WebKit, a view in a window of reel's own, or in a Chromium-based browser over DevTools.
/// Points are the page's, from its top left.
protocol Page: AnyObject {
    /// Evaluates JavaScript that returns numbers (an element's box), or nil when it returns null.
    func numbers(_ script: String) async throws -> [Double]?
    func mouse(_ action: MouseAction, at point: CGPoint) async throws
    func wheel(dx: Double, dy: Double, at point: CGPoint) async throws
    /// Types one character as a key press.
    func type(_ text: String) async throws
    /// Presses and releases a key with its modifiers; an editing shortcut (`WebDriver.commands`) as its command.
    func key(_ combo: KeyCombo) async throws
    /// Goes to `url` and waits until the new page has loaded.
    func navigate(to url: URL) async throws
}

enum MouseAction {
    case move, down, up
}

/// Plays a tape's steps against a web page. Input goes to the page, not the screen: the tape takes neither the mouse
/// nor the keyboard. The real cursor never moves, so the driver keeps a cursor of its own, glides it as the native
/// driver does, and keeps its path for render to draw.
final class WebDriver: Driving {
    static let glide: Duration = .milliseconds(350)
    static let press: Duration = .milliseconds(60)
    static let poll: Duration = .milliseconds(100)
    /// Pixels a `Scroll` line moves.
    static let line = 60.0

    let page: any Page
    let tape: Tape
    /// Where the drawn cursor is, in points from the page's top left.
    private(set) var cursor: CGPoint
    /// The cursor's path through the take, for render.
    private(set) var track: [Take.Sample] = []
    /// Milliseconds since the take's first frame; set once recording starts.
    var clock: (() -> Int)?

    init(page: any Page, tape: Tape, viewport: CGSize) {
        self.page = page
        self.tape = tape
        cursor = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
    }

    func perform(_ command: Command) async throws -> CGRect? {
        switch command {
        case let .sleep(duration):
            try await Task.sleep(for: duration)
        case .caption, .say, .reach, .speed, .hide:
            break
        case .code, .go, .focus, .mark, .callout, .expect:
            throw ReelError("a screen's steps are not for a web page")
        case let .wait(target):
            _ = try await element(target, scroll: false)
        case let .click(target):
            let point = if case let .point(p) = target { p } else { try await element(target, scroll: true).center }
            try await glide(to: point)
            try await mouse(.down, at: point)
            try await Task.sleep(for: Self.press)
            try await mouse(.up, at: point)
            return CGRect(origin: point, size: .zero)
        case let .type(text, pause):
            for character in text {
                try await type(character)
                try await Task.sleep(for: pause ?? tape.typingSpeed)
            }
        case let .key(combo, count):
            for _ in 0 ..< count {
                try await page.key(combo)
                try await Task.sleep(for: Self.press)
            }
        case let .scroll(direction, lines, over):
            if let over {
                let point = if case let .point(p) = over { p } else { try await element(over, scroll: false).center }
                try await glide(to: point)
            }
            let (dx, dy): (Double, Double) = switch direction {
            case .up: (0, -Self.line)
            case .down: (0, Self.line)
            case .left: (-Self.line, 0)
            case .right: (Self.line, 0)
            }
            for _ in 0 ..< lines {
                try await page.wheel(dx: dx, dy: dy, at: cursor)
                try await Task.sleep(for: .milliseconds(40))
            }
        case let .zoom(target, _, _):
            if case let .element(found) = target { return try await element(found, scroll: false).frame }
        case let .open(url):
            try await page.navigate(to: url)
        }
        return nil
    }

    func currentFrame(of target: Target) async -> CGRect? {
        try? await find(target, scroll: false)
    }

    /// Starts the cursor's path where it rests now.
    func startTrack() {
        record(cursor)
    }

    // MARK: Elements

    /// Waits, as long as the tape allows, for the element to show; scrolled into the middle of the page when asked.
    private func element(_ target: Target, scroll: Bool) async throws -> (frame: CGRect, center: CGPoint) {
        let deadline = ContinuousClock.now + tape.waitTimeout
        while true {
            if let frame = try await find(target, scroll: scroll) {
                return (frame, CGPoint(x: frame.midX, y: frame.midY))
            }
            if ContinuousClock.now > deadline {
                throw ReelError("no element \(target) appeared on the page within \(tape.waitTimeout)")
            }
            try await Task.sleep(for: Self.poll)
        }
    }

    private func find(_ target: Target, scroll: Bool) async throws -> CGRect? {
        guard let script = Self.finder(for: target, scroll: scroll) else { return nil }
        guard let box = try await page.numbers(script), box.count == 4 else { return nil }
        return CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
    }

    /// JavaScript returning the target's box `[x, y, width, height]` in the page's points, or null. A label matches
    /// an element's accessible name, placeholder, value or text exactly; controls are preferred over other elements,
    /// then the smallest, so a button wins over the panel around it. `#id` is an element id or a `data-testid`.
    static func finder(for target: Target, scroll: Bool) -> String? {
        let query: String
        switch target {
        case let .label(text): query = "{label: \(literal(text))}"
        case let .identifier(id): query = "{id: \(literal(id))}"
        case let .css(selector): query = "{css: \(literal(selector))}"
        case .point: return nil
        }
        return """
        (() => {
          const q = \(query);
          const shows = e => { const r = e.getBoundingClientRect(), s = getComputedStyle(e);
            return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
          const norm = t => (t || '').replace(/\\s+/g, ' ').trim();
          let found = null;
          if (q.css) found = [...document.querySelectorAll(q.css)].find(shows) || null;
          if (q.id) found = document.getElementById(q.id) || document.querySelector(`[data-testid="${CSS.escape(q.id)}"]`);
          if (q.label) {
            const control = e => e.matches('button, a, input, select, textarea, summary, label, [role=button], [role=link], [role=tab], [role=menuitem], [role=checkbox], [role=option]');
            const names = e => [e.getAttribute('aria-label'), e.getAttribute('placeholder'), e.getAttribute('title'),
              e.getAttribute('alt'), (e.tagName === 'INPUT' && /^(button|submit|reset)$/.test(e.type)) ? e.value : null,
              e.innerText].map(norm);
            const matches = [...document.querySelectorAll('body *')].filter(e => shows(e) && names(e).includes(q.label));
            const area = e => { const r = e.getBoundingClientRect(); return r.width * r.height; };
            matches.sort((a, b) => (control(b) - control(a)) || (area(a) - area(b)));
            found = matches[0] || null;
          }
          if (!found || !shows(found)) return null;
          \(scroll ? "found.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});" : "")
          const r = found.getBoundingClientRect();
          return [r.x, r.y, r.width, r.height];
        })()
        """
    }

    /// A JavaScript string literal.
    static func literal(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [text])
        return data.map { String(decoding: $0, as: UTF8.self).dropFirst().dropLast() }.map(String.init) ?? "\"\""
    }

    // MARK: Input

    /// Moves the cursor along an eased line, a step every 8 ms, telling the page as it goes (hovers show).
    private func glide(to target: CGPoint) async throws {
        let start = cursor
        let steps = max(1, Int(Self.glide / .milliseconds(8)))
        for step in 1 ... steps {
            let t = Easing.easeInOut(Double(step) / Double(steps))
            let point = CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)
            try await mouse(.move, at: point)
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    private func mouse(_ action: MouseAction, at point: CGPoint) async throws {
        cursor = point
        record(point)
        try await page.mouse(action, at: point)
    }

    private func record(_ point: CGPoint) {
        guard let ms = clock?() else { return }
        track.append(Take.Sample(ms: ms, frame: CGRect(origin: point, size: .zero)))
    }

    /// A character typed as a key press: the page sees keydown, input and keyup. Return and tab are keys.
    private func type(_ character: Character) async throws {
        switch character {
        case "\n": try await page.key(KeyCombo("return")!)
        case "\t": try await page.key(KeyCombo("tab")!)
        default: try await page.type(String(character))
        }
    }

    struct WebKey {
        var key: String
        var code: String
        var keyCode: Int
        var text: String?
    }

    /// Named keys, as the page sees them.
    static let keys: [String: WebKey] = {
        var keys: [String: WebKey] = [
            "return": WebKey(key: "Enter", code: "Enter", keyCode: 13, text: "\r"),
            "enter": WebKey(key: "Enter", code: "Enter", keyCode: 13, text: "\r"),
            "tab": WebKey(key: "Tab", code: "Tab", keyCode: 9),
            "space": WebKey(key: " ", code: "Space", keyCode: 32, text: " "),
            "delete": WebKey(key: "Backspace", code: "Backspace", keyCode: 8),
            "backspace": WebKey(key: "Backspace", code: "Backspace", keyCode: 8),
            "escape": WebKey(key: "Escape", code: "Escape", keyCode: 27),
            "esc": WebKey(key: "Escape", code: "Escape", keyCode: 27),
            "forwarddelete": WebKey(key: "Delete", code: "Delete", keyCode: 46),
            "home": WebKey(key: "Home", code: "Home", keyCode: 36), "end": WebKey(key: "End", code: "End", keyCode: 35),
            "pageup": WebKey(key: "PageUp", code: "PageUp", keyCode: 33),
            "pagedown": WebKey(key: "PageDown", code: "PageDown", keyCode: 34),
            "left": WebKey(key: "ArrowLeft", code: "ArrowLeft", keyCode: 37),
            "up": WebKey(key: "ArrowUp", code: "ArrowUp", keyCode: 38),
            "right": WebKey(key: "ArrowRight", code: "ArrowRight", keyCode: 39),
            "down": WebKey(key: "ArrowDown", code: "ArrowDown", keyCode: 40),
        ]
        for n in 1 ... 12 {
            keys["f\(n)"] = WebKey(key: "F\(n)", code: "F\(n)", keyCode: 111 + n)
        }
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            let upper = letter.uppercased()
            keys[String(letter)] = WebKey(
                key: String(letter), code: "Key\(upper)", keyCode: Int(upper.unicodeScalars.first!.value),
                text: String(letter)
            )
        }
        for digit in "0123456789" {
            keys[String(digit)] = WebKey(
                key: String(digit), code: "Digit\(digit)", keyCode: Int(digit.unicodeScalars.first!.value),
                text: String(digit)
            )
        }
        return keys
    }()

    /// Editing shortcuts by their normalised combo.
    static let commands = [
        "cmd+a": "selectAll", "cmd+c": "copy", "cmd+x": "cut", "cmd+v": "paste", "cmd+z": "undo",
        "shift+cmd+z": "redo",
    ]
}

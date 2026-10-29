import ApplicationServices
import CoreGraphics
import Foundation

/// Plays a tape's steps against the app with real input: the cursor glides to what it clicks, keys are typed one by
/// one, so the take shows what a person would see. Real input goes to whatever is in front, so the driver brings
/// the app forward first, and nobody should touch the mouse or keyboard while a tape plays.
///
/// Needs Accessibility, to find elements and to post input.
/// Plays a tape's steps against what it records: an app through Accessibility, or a web page over DevTools.
protocol Driving: AnyObject {
    /// Performs one step. Returns, for the timeline, where a click landed (an empty rect) or what a zoom framed, in
    /// points from the top left of what is recorded.
    func perform(_ command: Command) async throws -> CGRect?
    /// The element's frame now, without waiting; nil when it is gone.
    func currentFrame(of target: Target) async -> CGRect?
}

final class Driver: Driving {
    /// How long the cursor takes to reach what it clicks.
    static let glide: Duration = .milliseconds(350)
    /// Between a click's press and release, and between keys of a combo.
    static let press: Duration = .milliseconds(60)
    static let poll: Duration = .milliseconds(100)

    let app: AXNode
    let window: AXNode
    let tape: Tape
    private let source = CGEventSource(stateID: .hidSystemState)

    /// - Parameter frame: the window being recorded, in global points; the app's window nearest to it is driven.
    init(pid: pid_t, windowFrame frame: CGRect, tape: Tape) throws {
        app = AXNode(AXUIElementCreateApplication(pid))
        let windows = app.windows.compactMap { node in node.frame.map { (node, $0) } }
        guard let nearest = windows.min(by: { distance($0.1, frame) < distance($1.1, frame) }) else {
            throw ReelError("the app's window is not visible to Accessibility")
        }
        window = nearest.0
        self.tape = tape
    }

    /// Brings the app and its window to the front, so input reaches them.
    func activate() {
        app.set("AXFrontmost", kCFBooleanTrue)
        window.perform("AXRaise")
        window.set("AXMain", kCFBooleanTrue)
    }

    /// Input goes to whatever is in front, so a step never posts any while another app is: it brings the app back
    /// once, and stops the tape if that does not work.
    private func ensureInFront() async throws {
        if frontmost { return }
        activate()
        try await Task.sleep(for: .milliseconds(300))
        if !frontmost {
            throw ReelError("the app is not in front, so the tape stopped rather than send input to another app")
        }
    }

    private var frontmost: Bool {
        (app.attribute("AXFrontmost") as? Bool) == true
    }

    func resize(to size: CGSize) throws {
        var value = size
        guard let ax = AXValueCreate(.cgSize, &value), window.set("AXSize", ax) else {
            throw ReelError("the window cannot be resized")
        }
    }

    var windowFrame: CGRect {
        get throws {
            guard let frame = window.frame else { throw ReelError("the window is gone") }
            return frame
        }
    }

    /// Performs one step. Returns, for the timeline, where a click landed (an empty rect) or what a zoom framed, in
    /// points from the window's top left.
    func perform(_ command: Command) async throws -> CGRect? {
        switch command {
        case .sleep, .wait, .caption, .say, .reach, .zoom, .speed, .hide, .open: break
        default: try await ensureInFront()
        }
        switch command {
        case let .sleep(duration):
            try await Task.sleep(for: duration)
        case .caption, .say, .reach, .speed, .hide:
            // Narration runs on the recorder's speech clock; the rest is render's.
            break
        case .open:
            throw ReelError("Open goes to a web page; this tape launched an app")
        case let .zoom(target, _, _):
            if case let .element(element) = target { return try await frame(of: element) }
        case let .wait(target):
            _ = try await element(target)
        case let .click(target):
            let frame = try windowFrame
            let point = switch target {
            case let .point(p): CGPoint(x: frame.minX + p.x, y: frame.minY + p.y)
            default: try await element(target).center
            }
            try await glide(to: point)
            try await click(at: point)
            return CGRect(x: point.x - frame.minX, y: point.y - frame.minY, width: 0, height: 0)
        case let .type(text, pause):
            for character in text {
                try await type(character)
                try await Task.sleep(for: pause ?? tape.typingSpeed)
            }
        case let .key(combo, count):
            for _ in 0 ..< count {
                try await key(combo.keyCode, flags: combo.modifiers.flags)
            }
        case let .scroll(direction, lines, over):
            let frame = try windowFrame
            switch over {
            case let .point(p): try await glide(to: CGPoint(x: frame.minX + p.x, y: frame.minY + p.y))
            case let .some(target): try await glide(to: element(target).center)
            case nil: if !frame.contains(cursor) { try await glide(to: CGPoint(x: frame.midX, y: frame.midY)) }
            }
            for _ in 0 ..< lines {
                scroll(direction)
                try await Task.sleep(for: .milliseconds(40))
            }
        }
        return nil
    }

    /// The element's frame in points from the window's top left, waiting for it as `Wait` does.
    func frame(of target: Target) async throws -> CGRect {
        let window = try windowFrame
        guard let frame = try await element(target).node.frame else { throw ReelError("\(target) has no frame") }
        return frame.offsetBy(dx: -window.minX, dy: -window.minY)
    }

    /// The element's frame now, from the window's top left, without waiting: nil when it is gone.
    func currentFrame(of target: Target) -> CGRect? {
        guard let window = try? windowFrame else { return nil }
        let roots = [self.window] + app.windows.filter { !CFEqual($0.element, self.window.element) }
        return ElementSearch.find(target, in: roots, within: screens)?.frame?
            .offsetBy(dx: -window.minX, dy: -window.minY)
    }

    /// Where the cursor is, from the window's top left.
    var cursorInWindow: CGPoint? {
        guard let window = try? windowFrame else { return nil }
        return CGPoint(x: cursor.x - window.minX, y: cursor.y - window.minY)
    }

    /// Polls for the element until the tape's wait timeout.
    private func element(_ target: Target) async throws -> (node: AXNode, center: CGPoint) {
        let deadline = ContinuousClock.now + tape.waitTimeout
        while true {
            // Sheets, popovers and menus are windows of their own; search them all, the driven window first.
            let roots = [window] + app.windows.filter { !CFEqual($0.element, window.element) }
            if let node = ElementSearch.find(target, in: roots, within: screens),
               let frame = node.frame
            {
                return (node, CGPoint(x: frame.midX, y: frame.midY))
            }
            if ContinuousClock.now > deadline {
                throw ReelError("no element \(target) appeared within \(tape.waitTimeout)")
            }
            try await Task.sleep(for: Self.poll)
        }
    }

    /// Every display, in global points: an element scrolled out of sight has a frame, but not one on a screen.
    private var screens: CGRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
    }

    private var cursor: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Moves the cursor along an eased line, a step every 8 ms.
    private func glide(to target: CGPoint) async throws {
        let start = cursor
        let steps = max(1, Int(Self.glide / .milliseconds(8)))
        for step in 1 ... steps {
            let t = Double(step) / Double(steps)
            let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            let point = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            post(CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left
            ))
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    private func click(at point: CGPoint) async throws {
        post(CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ))
        try await Task.sleep(for: Self.press)
        post(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left))
    }

    /// Return and tab are keys; anything else is sent as the character itself, whatever the keyboard layout.
    private func type(_ character: Character) async throws {
        switch character {
        case "\n": return try await key(KeyCombo.keys["return"]!, flags: [])
        case "\t": return try await key(KeyCombo.keys["tab"]!, flags: [])
        default: break
        }
        let units = Array(String(character).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.flags = []
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(event)
        }
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags) async throws {
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        post(down)
        try await Task.sleep(for: Self.press)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        post(up)
        try await Task.sleep(for: Self.press)
    }

    private func scroll(_ direction: ScrollDirection) {
        let (dy, dx): (Int32, Int32) = switch direction {
        case .up: (1, 0)
        case .down: (-1, 0)
        case .left: (0, 1)
        case .right: (0, -1)
        }
        post(CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0))
    }

    private func post(_ event: CGEvent?) {
        event?.post(tap: .cghidEventTap)
    }
}

private func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
    abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
}

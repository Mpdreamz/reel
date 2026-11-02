import AppKit
import ReelEvents
import SwiftUI

/// A red frame round each window being recorded, and a pill beside it saying the step: only for captures that keep
/// this app out (its pid in their `excluded`), so the take never shows them. They never take a click or focus.
@MainActor
final class Overlays {
    private var frames: [String: OverlayPanel] = [:]
    private var pills: [String: OverlayPanel] = [:]
    private let me = ProcessInfo.processInfo.processIdentifier

    func update(_ runs: [RunState]) {
        var wanted: Set<String> = []
        for run in runs where run.ok == nil && !run.gone {
            for (subject, window) in run.overlays(for: me) {
                let key = "\(run.pid)/\(subject)"
                wanted.insert(key)
                let rect = Self.cocoa(window)
                frame(key).show(Frame(), at: rect.insetBy(dx: -4, dy: -4))
                let text = Self.pill(run, subject: subject)
                let pill = pill(key)
                pill.show(Pill(text: text), at: Self.place(pillOf: Pill.size(text), beside: rect))
            }
        }
        for key in Set(frames.keys).subtracting(wanted) {
            frames.removeValue(forKey: key)?.close()
            pills.removeValue(forKey: key)?.close()
        }
    }

    private func frame(_ key: String) -> OverlayPanel {
        if let panel = frames[key] { return panel }
        let panel = OverlayPanel()
        frames[key] = panel
        return panel
    }

    private func pill(_ key: String) -> OverlayPanel {
        if let panel = pills[key] { return panel }
        let panel = OverlayPanel()
        pills[key] = panel
        return panel
    }

    /// "● line 12 · Click "Play" · 3/14", the scene first in a reel of scenes, the track's name for a track.
    static func pill(_ run: RunState, subject: String) -> String {
        var parts: [String] = []
        if let scene = run.scene { parts.append("scene \(scene.index)/\(scene.count)") }
        if !subject.isEmpty { parts.append(subject) }
        if let step = run.steps[subject] {
            parts.append("line \(step.line) · \(step.source) · \(step.index)/\(step.count)")
        } else {
            parts.append("recording")
        }
        return "● " + parts.joined(separator: " · ")
    }

    /// Global points from the main display's top left, y down, as AppKit has them: from its bottom left, y up.
    static func cocoa(_ rect: RunEvent.Rect) -> NSRect {
        let main = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.x, y: main - rect.y - rect.height, width: rect.width, height: rect.height)
    }

    /// Below the window when there is room on its display, else above it, else inside its bottom edge (allowed:
    /// this app is kept out of the take).
    static func place(pillOf size: NSSize, beside window: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(window) }?.visibleFrame ?? window
        let x = min(max(window.minX, screen.minX + 8), screen.maxX - size.width - 8)
        let gap = 10.0
        if window.minY - gap - size.height >= screen.minY {
            return NSRect(x: x, y: window.minY - gap - size.height, width: size.width, height: size.height)
        }
        if window.maxY + gap + size.height <= screen.maxY {
            return NSRect(x: x, y: window.maxY + gap, width: size.width, height: size.height)
        }
        return NSRect(x: x + gap, y: window.minY + gap, width: size.width, height: size.height)
    }
}

/// A window of one transparent point, always on screen. ScreenCaptureKit lists an app only once it has a window on
/// screen, and a menu bar item does not count: without this reel could not see the companion to keep it out, and the
/// companion draws its overlay only once it is kept out.
@MainActor
enum Presence {
    private static var panel: OverlayPanel?

    static func show() {
        let panel = OverlayPanel()
        let screen = NSScreen.screens.first?.frame ?? .zero
        panel.setFrame(NSRect(x: screen.minX, y: screen.minY, width: 1, height: 1), display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

/// A borderless, see-through panel that is never key, never main, never activates the app and lets every click
/// through to what is under it: reel's clicks are real ones, at points on the screen.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func show(_ view: some View, at rect: NSRect) {
        if let host = contentView as? NSHostingView<AnyView> {
            host.rootView = AnyView(view)
        } else {
            contentView = NSHostingView(rootView: AnyView(view))
        }
        if frame != rect { setFrame(rect, display: true) }
        if !isVisible { orderFrontRegardless() }
    }
}

private struct Frame: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color(nsColor: Brand.recording), lineWidth: 2)
    }
}

private struct Pill: View {
    let text: String
    static let font = NSFont.systemFont(ofSize: 12, weight: .medium)

    static func size(_ text: String) -> NSSize {
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: min(640, width.rounded(.up) + 28), height: 26)
    }

    var body: some View {
        Text(text)
            .font(Font(Self.font))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(Color(red: 0x11 / 255, green: 0x19 / 255, blue: 0x23 / 255).opacity(0.92)))
            .overlay(Capsule().strokeBorder(Color(nsColor: Brand.recording), lineWidth: 1))
    }
}

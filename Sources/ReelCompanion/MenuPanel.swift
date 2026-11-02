import AppKit
import SwiftUI

/// The panel the menu bar item opens. Not an NSPopover: a popover makes the app active, and an app that becomes
/// active while a take records takes the front from the app reel drives, which stops the take. This panel takes
/// clicks without the app ever becoming active, and closes on a click anywhere else.
@MainActor
final class MenuPanel: NSPanel {
    private let host: NSHostingView<AnyView>
    private var outside: Any?

    init(_ content: some View) {
        host = NSHostingView(rootView: AnyView(content))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            host.topAnchor.constraint(equalTo: background.topAnchor),
            host.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    /// Key, so its buttons take a click; never main, and the app stays inactive (`.nonactivatingPanel`).
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Opens under `anchor` (the menu bar item's frame, in screen points).
    func open(under anchor: NSRect) {
        fit(under: anchor)
        orderFrontRegardless()
        outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Sized to what it shows, kept under `anchor` and on its display.
    func fit(under anchor: NSRect) {
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: true)
    }

    override func close() {
        if let outside { NSEvent.removeMonitor(outside) }
        outside = nil
        super.close()
    }
}

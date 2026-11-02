import AppKit
import ReelEvents
import SwiftUI

// Reel Companion: a menu bar app that shows what each run of reel is doing (its scenes and steps while it records,
// each pass of the render, which profile, which Output, how far), read from the runs folder reel writes its events
// to, and a red frame and a pill on the window being recorded, which the take never shows. Built into
// build/Reel Companion.app by scripts/companion.sh.

@MainActor
final class Companion: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var panel = MenuPanel(RunsView(model: model))
    private let folder = RunFolder()
    private let model = Model()
    private let overlays = Overlays()
    private var timer: Timer?

    func applicationDidFinishLaunching(_: Notification) {
        try? FileManager.default.createDirectory(at: folder.folder, withIntermediateDirectories: true)
        Presence.show()
        item.button?.image = Symbol.image()
        item.button?.toolTip = "reel"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        refresh()
        // `open "Reel Companion.app" --args --open` shows the panel at once, without a click on the menu bar.
        if CommandLine.arguments.contains("--open") {
            // Once the menu bar has placed the item: shown before, the panel has nothing to hang from.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.toggle() }
        }
        // Four times a second: a pass says how far it is at most ten.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    @objc private func toggle() {
        if panel.isVisible {
            panel.close()
        } else if let anchor = item.button?.window?.frame {
            panel.open(under: anchor)
        }
    }

    private func refresh() {
        guard folder.read() else { return }
        let runs = folder.ordered
        model.runs = runs
        if panel.isVisible, let anchor = item.button?.window?.frame {
            // Once SwiftUI has laid out what changed.
            DispatchQueue.main.async { self.panel.fit(under: anchor) }
        }
        overlays.update(runs)
        let live = runs.filter { $0.ok == nil && !$0.gone }
        let recording = live.contains { $0.stage == .recording }
        let rendering = live.first { $0.stage == .rendering }?.pass?.fraction
        item.button?.image = Symbol.image(progress: recording ? nil : rendering)
        item.button?.contentTintColor = recording ? Brand.recording : nil
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let companion = Companion()
app.delegate = companion
app.run()

// An app that starts in the middle of a take: once a reel's capture starts (its `recording` event in the runs
// folder), it waits a moment, then shows a magenta square in the middle of what is recorded, for a few seconds. It never activates and lets every click through. scripts/check-take.swift checks the
// take never shows it. It writes when it showed and hid the square (milliseconds since 1970) to <log>.
//
// swiftc -o build/intruder scripts/intruder.swift && build/intruder <log>
import AppKit

let log = URL(fileURLWithPath: CommandLine.arguments[1])
let runs = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/reel/runs", directoryHint: .isDirectory)
let started = Date()
func now() -> Int {
    Int((Date().timeIntervalSince1970 * 1000).rounded())
}

/// What a run that started after this did is capturing, in global points from the main display's top left, once it is.
func capturing() -> NSRect? {
    let files = (try? FileManager.default.contentsOfDirectory(
        at: runs, includingPropertiesForKeys: [.contentModificationDateKey]
    )) ?? []
    for file in files {
        guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              modified > started, let text = try? String(contentsOf: file, encoding: .utf8)
        else { continue }
        for line in text.split(separator: "\n") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  event["kind"] as? String == "recording", event["phase"] as? String == "start",
                  let window = event["window"] as? [String: Double],
                  let x = window["x"], let y = window["y"], let width = window["width"], let height = window["height"]
            else { continue }
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }
    return nil
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let side = 200.0
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: .borderless, backing: .buffered, defer: false
)
window.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
window.level = .floating
window.ignoresMouseEvents = true
window.hasShadow = false

var shownAt = 0
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
    guard Date().timeIntervalSince(started) < 60 else { exit(1) }
    guard let recorded = capturing() else { return }
    timer.invalidate()
    // Cocoa's y goes up from the main display's bottom.
    let main = NSScreen.screens[0].frame.height
    window.setFrameOrigin(NSPoint(x: recorded.midX - side / 2, y: main - recorded.midY - side / 2))
    Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
        window.orderFrontRegardless()
        shownAt = now()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            window.orderOut(nil)
            try? "\(shownAt) \(now())\n".write(to: log, atomically: true, encoding: .utf8)
            exit(0)
        }
    }
}
app.run()

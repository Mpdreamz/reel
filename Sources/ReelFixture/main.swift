import AppKit
import AVFoundation

// The app reel's own tapes record. A counter that ticks every second, a Play button that starts a quiet 440 Hz
// tone (silence before the click, a tone after it), a text field and a list to scroll. What happens is logged to
// fixture-events.log next to the app, so scripts/live.sh can check what a tape did. Built into
// build/ReelFixture.app by scripts/fixture.sh.

@MainActor
final class Fixture: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSTableViewDataSource {
    let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 480, height: 360),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
    )
    let counter = NSTextField(labelWithString: "0")
    let play = NSButton(title: "Play", target: nil, action: nil)
    let name = NSTextField(string: "")
    let echo = NSTextField(labelWithString: "")
    let table = NSTableView()
    let engine = AVAudioEngine()
    let log: FileHandle?
    var ticks = 0

    override init() {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "fixture-events.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        log = try? FileHandle(forWritingTo: url)
    }

    func applicationDidFinishLaunching(_: Notification) {
        window.title = "Reel Fixture"

        counter.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        play.target = self
        play.action = #selector(startTone)
        play.setAccessibilityIdentifier("play")
        name.placeholderString = "Name"
        name.setAccessibilityIdentifier("name")
        name.delegate = self
        echo.setAccessibilityIdentifier("echo")

        table.addTableColumn(NSTableColumn(identifier: .init("row")))
        table.headerView = nil
        table.dataSource = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.setAccessibilityIdentifier("list")
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.record("scroll \(Int(scroll.contentView.bounds.minY))") }
        }

        let stack = NSStackView(views: [counter, NSStackView(views: [play, name]), echo, scroll])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            name.widthAnchor.constraint(equalToConstant: 200),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])

        // The standard Edit menu: without it, AppKit's key equivalents such as cmd+a do nothing.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let menu = NSMenu()
        menu.addItem(withTitle: "ReelFixture", action: nil, keyEquivalent: "").submenu = {
            let app = NSMenu()
            app.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            return app
        }()
        menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = menu

        window.makeKeyAndOrderFront(nil)
        // Focus starts on the list, so typing only reaches the field after a tape clicks it.
        window.makeFirstResponder(table)
        NSApp.activate()
        record("launched")
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.ticks += 1
                self.counter.stringValue = "\(self.ticks)"
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func controlTextDidChange(_: Notification) {
        echo.stringValue = name.stringValue
    }

    func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { record("submit \(name.stringValue)") }
        return false
    }

    func numberOfRows(in _: NSTableView) -> Int {
        100
    }

    func tableView(_: NSTableView, objectValueFor _: NSTableColumn?, row: Int) -> Any? {
        "Row \(row + 1)"
    }

    @objc func startTone() {
        guard !engine.isRunning else { return }
        record("play")
        let rate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let source = AVAudioSourceNode(renderBlock: Self.tone(rate: rate))
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(
            standardFormatWithSampleRate: rate, channels: 1
        ))
        try? engine.start()
    }

    private func record(_ event: String) {
        log?.write(Data("\(event)\n".utf8))
    }

    /// Nonisolated: Core Audio calls it on its own thread, and a block made on the main actor traps there.
    private nonisolated static func tone(rate: Double) -> AVAudioSourceNodeRenderBlock {
        let step = 2 * Double.pi * 440 / rate
        var phase = 0.0
        // Mono, so one buffer.
        return { _, _, frames, buffers -> OSStatus in
            let samples = UnsafeMutableAudioBufferListPointer(buffers)[0].mData!.assumingMemoryBound(to: Float.self)
            for i in 0 ..< Int(frames) {
                samples[i] = Float(0.1 * sin(phase))
                phase += step
            }
            phase = phase.truncatingRemainder(dividingBy: 2 * .pi)
            return noErr
        }
    }
}

let app = NSApplication.shared
let delegate = Fixture()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

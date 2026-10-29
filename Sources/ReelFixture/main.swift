import AppKit
import AVFoundation

// The app reel's own tapes record: a window that changes every second and a quiet 440 Hz tone from launch, so a
// take can be checked for both picture and sound. Built into build/ReelFixture.app by scripts/fixture.sh.

@MainActor
final class Fixture: NSObject, NSApplicationDelegate {
    let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 480, height: 300),
        styleMask: [.titled, .closable], backing: .buffered, defer: false
    )
    let label = NSTextField(labelWithString: "0")
    let engine = AVAudioEngine()
    var ticks = 0

    func applicationDidFinishLaunching(_: Notification) {
        window.title = "Reel Fixture"
        label.font = .monospacedDigitSystemFont(ofSize: 96, weight: .bold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 90, width: 480, height: 120)
        window.contentView?.addSubview(label)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.ticks += 1
                self.label.stringValue = "\(self.ticks)"
            }
        }
        playTone()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    private func playTone() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let rate = format.sampleRate
        let source = AVAudioSourceNode(renderBlock: Self.tone(rate: rate))
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(
            standardFormatWithSampleRate: rate, channels: 1
        ))
        try? engine.start()
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

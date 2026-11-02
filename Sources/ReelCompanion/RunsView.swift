import AppKit
import ReelEvents
import SwiftUI

/// The runs, as the menu bar's panel shows them.
@MainActor @Observable
final class Model {
    var runs: [RunState] = []
}

/// The brand's colours (design/brand/themes/tokens.json).
enum Brand {
    static let gate = Color(red: 0xF2 / 255, green: 0xB0 / 255, blue: 0x4C / 255)
    static let signal = Color(red: 0x5C / 255, green: 0xC8 / 255, blue: 0xB6 / 255)
    /// What says a take is recording: the overlay's frame, the menu bar's symbol.
    static let recording = NSColor(srgbRed: 0.93, green: 0.23, blue: 0.23, alpha: 1)
    static let red = Color(nsColor: recording)
}

struct RunsView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("reel").font(.headline)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .font(.caption)
            }
            let live = model.runs.filter { $0.ok == nil && !$0.gone }
            let done = model.runs.filter { $0.ok != nil || $0.gone }
            if model.runs.isEmpty {
                Text("No reel is running. `reel <file>.reel` shows here as it records and renders.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(live) { RunCard(run: $0) }
            if !done.isEmpty {
                Text("Recent").font(.caption).foregroundStyle(.secondary).padding(.top, live.isEmpty ? 0 : 4)
                ForEach(done) { FinishedRow(run: $0) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

/// A run going on: its reel, what it is doing, and how far.
struct RunCard: View {
    let run: RunState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(run.name).font(.system(.body, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(stage).font(.caption).foregroundStyle(.secondary)
            }
            if let scene = run.scene {
                Text("scene \(scene.index) of \(scene.count): \(scene.reel)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if run.stage == .recording {
                ForEach(run.steps.keys.sorted(), id: \.self) { subject in
                    if let step = run.steps[subject] { StepRow(subject: subject, step: step) }
                }
            }
            if let pass = run.pass, run.stage == .rendering || pass.name == .draw {
                PassRow(pass: pass)
            } else if run.stage == .starting, let note = run.note {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }

    private var color: Color {
        run.stage == .recording ? Brand.red : Brand.gate
    }

    private var stage: String {
        switch run.stage {
        case .starting: "starting"
        case .recording: "recording"
        case .rendering: "rendering"
        case .finished: "done"
        case .failed: "failed"
        case .gone: "stopped"
        }
    }
}

struct StepRow: View {
    let subject: String
    let step: RunState.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                LineIcon(command: step.source)
                Text(step.source).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(subject.isEmpty ? "" : subject + " · ")line \(step.line) · \(step.index)/\(step.count)")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(step.index - (step.running ? 1 : 0)), total: Double(max(1, step.count)))
                .tint(Brand.red)
        }
    }
}

struct PassRow: View {
    let pass: RunEvent.Pass

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(Self.title(pass.name)).font(.caption.weight(.medium))
                if let output = pass.output { Text(output).font(.caption).lineLimit(1).truncationMode(.middle) }
                Spacer()
                Text("\(Int((pass.fraction * 100).rounded()))%").font(.caption2).monospacedDigit()
            }
            ProgressView(value: pass.fraction).tint(Brand.gate)
            let details = [
                pass.profile.map { "profile \($0)" }, pass.detail,
                pass.attempt.flatMap { $0 > 1 ? "try \($0), to fit its size" : nil },
            ].compactMap(\.self)
            if !details.isEmpty {
                Text(details.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    static func title(_ name: RunEvent.Pass.Name) -> String {
        switch name {
        case .draw: "Drawing"
        case .render: "Rendering"
        case .frame: "Framing"
        case .join: "Joining"
        case .tracks: "Drawing tracks"
        case .encode: "Encoding"
        case .gif: "Writing GIF"
        }
    }
}

/// A finished run: how it ended, and what it wrote, each shown in the Finder on a click.
struct FinishedRow: View {
    let run: RunState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(run.ok == true ? Brand.signal : Brand.red)
                Text(run.name).font(.callout).lineLimit(1)
                Spacer()
                Text(Date(timeIntervalSince1970: Double(run.updatedAt) / 1000), style: .relative)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let failure = run.failure {
                Text(failure).font(.caption).foregroundStyle(Brand.red).lineLimit(3)
            } else if run.gone {
                Text("stopped without finishing").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(run.written, id: \.path) { file in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                } label: {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent).font(.caption).lineLimit(1)
                }
                .buttonStyle(.link)
                .help(file.summary)
            }
        }
    }

    private var icon: String {
        run.ok == true ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
}

/// The brand's line icon for a step's command (design/brand/line-icons), when it has one.
struct LineIcon: View {
    let command: String

    var body: some View {
        if let image = Self.image(for: command) {
            Image(nsImage: image).renderingMode(.template).resizable().frame(width: 14, height: 14)
                .foregroundStyle(.secondary)
        }
    }

    static let names: [String: String] = [
        "Click": "click", "Type": "type", "Key": "key", "Say": "say", "Wait": "wait", "Sleep": "wait",
        "Zoom": "zoom", "Launch": "launch", "Open": "web", "Attach": "launch", "Scroll": "scroll",
        "Caption": "caption", "Hide": "hide-show", "Show": "hide-show", "Speed": "speed",
    ]

    static func image(for command: String) -> NSImage? {
        let word = command.prefix { $0.isLetter }
        guard let name = names[String(word)],
              let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "line-icons"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }
}

import Foundation
@testable import ReelEvents
import Testing

private func event(_ kind: RunEvent.Kind, at: Int = 1, track: String? = nil) -> RunEvent {
    RunEvent(at: at, pid: 7, track: track, kind: kind)
}

private let window = RunEvent.Rect(x: 100, y: 80, width: 640, height: 480)

private func fold(_ events: [RunEvent]) -> RunState {
    var run = RunState(pid: 7)
    for event in events {
        run.apply(event)
    }
    return run
}

struct RunStateTests {
    @Test func aRunGoesFromStartingToRecordingToRenderingToDone() {
        var run = RunState(pid: 7)
        run.apply(event(.started(reel: "/a/demo.reel", command: "run", scenes: [], profiles: ["github"], outputs: [])))
        #expect(run.stage == .starting)
        #expect(run.name == "demo.reel")
        run.apply(event(.recording(phase: .start, window: window, excluded: [3])))
        run.apply(event(.step(line: 4, source: "Click \"Play\"", index: 1, count: 2, phase: .start)))
        #expect(run.stage == .recording)
        #expect(run.steps[""] == RunState.Step(line: 4, source: "Click \"Play\"", index: 1, count: 2, running: true))
        run.apply(event(.recording(phase: .end, window: nil, excluded: [])))
        run.apply(event(.pass(RunEvent.Pass(name: .encode, profile: "github", output: "d.mp4", fraction: 0.4))))
        #expect(run.stage == .rendering)
        #expect(run.pass?.fraction == 0.4)
        run.apply(event(.wrote(path: "/a/d.mp4", summary: "1 MB")))
        run.apply(event(.ended(ok: true), at: 9))
        #expect(run.stage == .finished)
        #expect(run.written == [RunState.Written(path: "/a/d.mp4", summary: "1 MB")])
        #expect(run.updatedAt == 9)
    }

    @Test func aFailedRunKeepsWhatItSaid() {
        let run = fold([event(.failed("line 3: no button Play")), event(.ended(ok: false))])
        #expect(run.stage == .failed)
        #expect(run.failure == "line 3: no button Play")
    }

    @Test func theOverlayIsDrawnOnlyWhereTheCompanionIsKeptOut() {
        let run = fold([event(.recording(phase: .start, window: window, excluded: [3]))])
        #expect(run.overlays(for: 5).isEmpty)
        #expect(run.overlays(for: 3).map(\.window) == [window])
    }

    @Test func aCompanionThatStartedMidTakeDrawsOnceItIsKeptOut() {
        var run = fold([event(.recording(phase: .start, window: window, excluded: [3]))])
        #expect(run.overlays(for: 5).isEmpty)
        run.apply(event(.excluded([5])))
        #expect(run.overlays(for: 5).map(\.window) == [window])
    }

    @Test func aScreenReelHasNoWindowToDrawOn() {
        let run = fold([event(.recording(phase: .start, window: nil, excluded: [5]))])
        #expect(run.stage == .recording)
        #expect(run.overlays(for: 5).isEmpty)
    }

    @Test func tracksAreFollowedEachOnItsOwn() {
        let other = RunEvent.Rect(x: 800, y: 80, width: 400, height: 300)
        var run = fold([
            event(.recording(phase: .start, window: window, excluded: [5]), track: "app"),
            event(.recording(phase: .start, window: other, excluded: [5]), track: "web"),
            event(.step(line: 3, source: "Click \"Go\"", index: 1, count: 1, phase: .start), track: "app"),
            // Kept out of one track's capture says nothing of the other's.
            event(.excluded([9]), track: "web"),
        ])
        #expect(run.overlays(for: 5).map(\.subject) == ["app", "web"])
        #expect(run.overlays(for: 9).map(\.subject) == ["web"])
        #expect(run.steps["app"]?.line == 3)
        #expect(run.steps["web"] == nil)
        run.apply(event(.recording(phase: .end, window: nil, excluded: []), track: "app"))
        #expect(run.overlays(for: 5).map(\.subject) == ["web"])
        run.apply(event(.ended(ok: true)))
        #expect(run.overlays(for: 5).isEmpty)
    }

    @Test func aNewSceneStartsItsStepsAfresh() {
        let run = fold([
            event(.scene(index: 1, count: 2, reel: "one.reel")),
            event(.step(line: 3, source: "Sleep 1s", index: 1, count: 1, phase: .end)),
            event(.scene(index: 2, count: 2, reel: "two.reel")),
        ])
        #expect(run.scene == RunState.Scene(index: 2, count: 2, reel: "two.reel"))
        #expect(run.steps.isEmpty)
    }
}

struct RunFolderTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "reel-runs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func append(_ data: Data, to pid: Int32) throws {
        let url = Runs.file(for: pid, in: folder)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(
            atPath: url.path,
            contents: nil
        ) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    @Test func aLineCountsOnceItIsWhole() throws {
        let runs = RunFolder(folder: folder, alive: { _ in true })
        let line = RunEvent(at: 1, pid: 42, kind: .note("hello")).line
        try append(line.prefix(10), to: 42)
        runs.read()
        #expect(runs.runs[42]?.note == nil)
        try append(line.dropFirst(10), to: 42)
        #expect(runs.read())
        #expect(runs.runs[42]?.note == "hello")
        // Nothing new: nothing changed.
        #expect(!runs.read())
    }

    @Test func aRunWhoseProcessWentIsStopped() throws {
        var alive = true
        let runs = RunFolder(folder: folder, alive: { _ in alive })
        try append(RunEvent(at: 1, pid: 42, kind: .note("recording")).line, to: 42)
        runs.read()
        #expect(runs.runs[42]?.stage == .recording || runs.runs[42]?.stage == .starting)
        alive = false
        #expect(runs.read())
        #expect(runs.runs[42]?.stage == .gone)
    }

    @Test func runsGoingOnComeFirstAndOnlyTheLatestFinishedAreKept() throws {
        let runs = RunFolder(folder: folder, keep: 2, alive: { _ in true })
        for pid: Int32 in 1 ... 4 {
            try append(RunEvent(at: Int(pid), pid: pid, kind: .ended(ok: true)).line, to: pid)
        }
        try append(RunEvent(at: 0, pid: 9, kind: .note("still going")).line, to: 9)
        runs.read()
        #expect(runs.ordered.map(\.pid) == [9, 4, 3])
    }

    @Test func aFileMadeAgainForThePidIsANewRun() throws {
        let runs = RunFolder(folder: folder, alive: { _ in true })
        try append(RunEvent(at: 1, pid: 42, kind: .note("a much longer first line")).line, to: 42)
        try append(RunEvent(at: 2, pid: 42, kind: .ended(ok: false)).line, to: 42)
        runs.read()
        try RunEvent(at: 3, pid: 42, kind: .note("again")).line.write(to: Runs.file(for: 42, in: folder))
        runs.read()
        #expect(runs.runs[42]?.note == "again")
        #expect(runs.runs[42]?.ok == nil)
    }
}

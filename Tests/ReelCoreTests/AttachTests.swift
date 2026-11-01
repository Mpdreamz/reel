import AppKit
import Foundation
@testable import ReelCore
import Testing

struct AttachTests {
    private let dir = URL(fileURLWithPath: "/tmp/demos", isDirectory: true)

    @Test func anAttachedAppIsATrack() throws {
        let tape = try Tape.parse("""
        Screen terminal as term
          Type "open -a Calculator"
          Key return
        Attach com.apple.calculator as calc
        Attach ./Musicbox.app as box
        Output a.mp4
        Wait for calc
        """, relativeTo: dir)
        #expect(tape.tracks.map(\.tape.launch) == [
            .screen(.terminal), .attach("com.apple.calculator"), .attach("/tmp/demos/Musicbox.app"),
        ])
        #expect(tape.tracks.map(\.isAttached) == [false, true, true])
        #expect(throws: TapeError(
            line: 1, message: "Attach records an app something else opens, as a track: Attach <app> as <name>"
        )) { try Tape.parse("Attach com.apple.calculator\nOutput a.mp4", relativeTo: dir) }
    }

    @Test func itFindsARunningAppByBundleIdOrPath() throws {
        let app = try #require(NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier != nil && $0.bundleURL != nil && !$0.isTerminated
        })
        #expect(Recorder.running(app.bundleIdentifier!) == app.processIdentifier)
        #expect(Recorder.running(app.bundleURL!.path) == app.processIdentifier)
        #expect(Recorder.running("com.example.nothing.at.all") == nil)
    }

    @Test func anAppThatNeverOpensSaysSo() async throws {
        let error = await #expect(throws: ReelError.self) {
            try await Recorder.attach("com.example.nothing.at.all", within: .milliseconds(250), log: { _ in })
        }
        #expect(error?.description == "com.example.nothing.at.all did not open within 250ms")
    }

    @Test func attachedTracksStopOnceEverythingElseHasPlayed() {
        let stop = Stop()
        let playing = Countdown(3) { stop.fire() }
        playing.done()
        playing.done()
        #expect(!stop.fired)
        playing.done()
        #expect(stop.fired)
    }
}

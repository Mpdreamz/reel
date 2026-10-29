import CoreGraphics
import Foundation
@testable import ReelCore
import Testing

struct OverlayPlanTests {
    /// A take of the actions in `tape`, each 1 s long and 1 s apart: action n runs from 2n to 2n + 1 seconds.
    private func plan(_ body: String, durationMs: Int = 10000, edit: ((inout [Take.Event]) -> Void)? = nil) throws
        -> [Overlay]
    {
        let tape = try Tape.parse("Launch x\nOutput a.mp4\n" + body, relativeTo: URL(fileURLWithPath: "/tmp"))
        var events = tape.actions.enumerated().map { index, step in
            let click = if case .click = step.command { true } else { false }
            return Take.Event(
                line: step.line, command: step.source, startMs: index * 2000, endMs: index * 2000 + 1000,
                x: click ? 40 : nil, y: click ? 30 : nil
            )
        }
        edit?(&events)
        let take = Take(
            width: 100, height: 100, scale: 2, frameRate: 30, audio: false, durationMs: durationMs, events: events
        )
        return try OverlayPlan.make(tape: tape, take: take)
    }

    @Test func captionsRunUntilTheNextOneAnchoredToTheActionBefore() throws {
        let overlays = try plan("""
        Caption "Hello"
        Sleep 1s
        Caption "Second"
        Sleep 1s
        Sleep 1s
        Caption off
        Sleep 1s
        Caption "Last"
        """)
        #expect(overlays == [
            Overlay(kind: .caption("Hello"), start: 0, end: 1),
            Overlay(kind: .caption("Second"), start: 1, end: 5),
            Overlay(kind: .caption("Last"), start: 7, end: 10),
        ])
    }

    @Test func otherRenderOnlyStepsAreNotActions() throws {
        // Zooms on a point, speeds and trims sit between captions without counting as actions of the take.
        let overlays = try plan("""
        Hide
        Sleep 1s
        Show
        Zoom @10,10 2x
        Caption "After the first"
        Speed 2x
        Sleep 1s
        Speed off
        Zoom off
        Caption "After the second"
        """)
        #expect(overlays.map(\.start) == [1, 3])
    }

    @Test func aDurationEndsACaptionEarlyButNeverLate() throws {
        let overlays = try plan("""
        Sleep 1s
        Caption "Short" 500ms
        Sleep 1s
        Caption "Long" 9s
        Sleep 1s
        Caption "Next"
        """)
        #expect(overlays.map(\.kind) == [.caption("Short"), .caption("Long"), .caption("Next")])
        #expect(overlays.map(\.start) == [1, 3, 5])
        #expect(overlays.map(\.end) == [1.5, 5, 10])
    }

    @Test func keyBadgesAndRipples() throws {
        let overlays = try plan("""
        Key cmd+shift+z
        Key down 3
        Click #play
        """)
        #expect(overlays == [
            Overlay(kind: .keys("⇧⌘Z"), start: 0, end: 1.6),
            Overlay(kind: .keys("↓ ×3"), start: 2, end: 3.6),
            Overlay(kind: .ripple(CGPoint(x: 40, y: 30)), start: 4.94, end: 5.44),
        ])
    }

    @Test func overlaysStopAtTheEndOfTheTake() throws {
        let overlays = try plan("Sleep 1s\nKey return", durationMs: 2500)
        #expect(overlays == [Overlay(kind: .keys("↩"), start: 2, end: 2.5)])
    }

    @Test func badgesAndRipplesCanBeTurnedOff() throws {
        #expect(try plan("Set KeyBadges off\nSet ClickRipples off\nLaunch y\nKey a\nClick #b".replacing(
            "Launch y\n", with: ""
        )).isEmpty)
    }

    @Test func aChangedActionNeedsANewTake() {
        #expect(throws: ReelError.self) { try plan("Sleep 1s\nSleep 2s") { $0.removeLast() } }
        #expect(throws: ReelError.self) { try plan("Sleep 1s") { $0[0].command = "Sleep 2s" } }
    }

    @Test func captionsChangeWithoutANewTake() throws {
        // Same actions, captions added, moved and reworded: the take still fits.
        #expect(try plan("Caption \"a\"\nSleep 1s\nCaption \"b\" 1s\nSleep 2s").count == 2)
    }

    @Test(arguments: [
        ("⌘S", "cmd+s"), ("⌃⌥⇧⌘K", "cmd+shift+opt+ctrl+k"), ("Space", "space"), ("F5", "f5"), ("fn ←", "fn+left"),
        ("⎋", "esc"), ("⇥", "tab"), ("/", "/"),
    ])
    func keySymbols(symbol: String, combo: String) throws {
        #expect(try #require(KeyCombo(combo)).symbol == symbol)
    }
}

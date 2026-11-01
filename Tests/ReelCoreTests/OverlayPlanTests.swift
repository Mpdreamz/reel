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

/// `Set Cursor`: a web reel's drawn cursor left out at render time; an app's real one left out of the recording.
struct CursorSettingTests {
    private let dir = URL(fileURLWithPath: "/tmp/reel-cursor-tests")

    private func parse(_ text: String) throws -> Tape {
        try Tape.parse(text, relativeTo: dir)
    }

    private func failure(_ text: String) -> String? {
        do {
            _ = try parse(text)
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// A web take: the driver's path kept, and render asked to draw it.
    private var webTake: Take {
        var take = Take(width: 320, height: 200, scale: 2, frameRate: 30, audio: false, durationMs: 1000, events: [])
        take.cursor = [Take.Sample(ms: 0, frame: CGRect(x: 20, y: 20, width: 0, height: 0))]
        take.drawnCursor = true
        return take
    }

    @Test func onUnlessSet() throws {
        #expect(try parse("Open https://example.com\nOutput a.mp4").cursor)
        #expect(try parse("Launch x\nOutput a.mp4").cursor)
        #expect(try !parse("Open https://example.com\nOutput a.mp4\nSet Cursor off").cursor)
        #expect(try parse("Open https://example.com\nOutput a.mp4\nSet Cursor off\nSet Cursor on").cursor)
        #expect(try !parse("Launch x\nOutput a.mp4\nSet Cursor off").cursor)
    }

    @Test func onOrOffOnlyAndNotOnAScreen() {
        #expect(failure("Open https://example.com\nSet Cursor hidden") ==
            "line 2: Cursor must be on or off, not 'hidden'")
        #expect(failure("Screen code\nSet Cursor off")
            == "line 2: Cursor is for web pages and apps; a code screen draws no cursor, only its caret")
        #expect(failure("Screen terminal\nSet Cursor off")
            == "line 2: Cursor is for web pages and apps; a terminal screen draws no cursor, only its caret")
    }

    @Test func renderLeavesTheDrawnCursorOut() throws {
        let web = try parse("Open https://example.com\nOutput a.mp4")
        #expect(OverlayPlan.drawsCursor(tape: web, take: webTake))
        let hidden = try parse("Open https://example.com\nOutput a.mp4\nSet Cursor off")
        #expect(!OverlayPlan.drawsCursor(tape: hidden, take: webTake))
        // An app's take has the real cursor in its picture: nothing is drawn over it either way.
        var app = webTake
        app.drawnCursor = nil
        #expect(!OverlayPlan.drawsCursor(tape: web, take: app))
    }

    @Test func aWebReelsCursorDiffersByProfile() throws {
        let tape = try parse("""
        Open https://example.com
        Output a.mp4
        Set Cursor social ? off : on
        Profile sting
          Set Cursor off
        """)
        #expect(tape.cursor)
        #expect(try !tape.with(profile: tape.profile(named: "social")).cursor)
        #expect(try !tape.with(profile: tape.profile(named: "sting")).cursor)
        #expect(try tape.with(profile: tape.profile(named: "github")).cursor)
        let sting = try tape.with(profile: tape.profile(named: "sting"))
        #expect(!OverlayPlan.drawsCursor(tape: sting, take: webTake))
    }

    @Test func anAppReelsCursorIsFixedWhenRecording() throws {
        #expect(failure("Launch x\nOutput a.mp4\nSet Cursor social ? off : on") == "line 3: \(Tape.appCursor)")
        let tape = try parse("Launch x\nOutput a.mp4\nSet Cursor off\nProfile sting\n  Set Cursor on")
        #expect(failure { try tape.with(profile: tape.profile(named: "sting")) }?.hasSuffix(Tape.appCursor) == true)
        let chosen = try parse("Launch x\nOutput a.mp4\nProfile sting\n  Set Cursor social ? off : on")
        #expect(failure { try chosen.with(profile: chosen.profile(named: "sting")) }?.hasSuffix(Tape.appCursor) == true)
        // A profile that leaves it as it is, or sets it to what it is, is fine.
        #expect(try !tape.with(profile: tape.profile(named: "social")).cursor)
        let same = try parse("Launch x\nOutput a.mp4\nSet Cursor off\nProfile sting\n  Set Cursor off")
        #expect(try !same.with(profile: same.profile(named: "sting")).cursor)
    }

    private func failure(_ work: () throws -> some Any) -> String? {
        do {
            _ = try work()
            return nil
        } catch {
            return "\(error)"
        }
    }
}

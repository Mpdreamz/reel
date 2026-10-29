import CoreGraphics
@testable import ReelCore
import Testing

struct KeyComboTests {
    @Test(arguments: [
        ("a", 0x00, [], "a"),
        ("return", 0x24, [], "return"),
        ("enter", 0x24, [], "enter"),
        ("cmd+s", 0x01, .command, "cmd+s"),
        ("Command+Shift+Z", 0x06, [.command, .shift], "shift+cmd+z"),
        ("alt+ctrl+tab", 0x30, [.option, .control], "ctrl+opt+tab"),
        ("f12", 0x6F, [], "f12"),
        ("fn+left", 0x7B, .function, "fn+left"),
    ] as [(String, CGKeyCode, KeyCombo.Modifiers, String)])
    func parses(text: String, code: CGKeyCode, modifiers: KeyCombo.Modifiers, name: String) throws {
        let combo = try #require(KeyCombo(text))
        #expect(combo.keyCode == code)
        #expect(combo.modifiers == modifiers)
        #expect(combo.description == name)
    }

    @Test(arguments: ["", "cmd", "cmd+", "+a", "hyper+a", "cmd+cmd+a", "command+cmd+a", "f13", "ab"])
    func rejects(text: String) {
        #expect(KeyCombo(text) == nil)
    }

    @Test func modifierFlags() {
        let flags = KeyCombo.Modifiers([.command, .shift, .option, .control, .function]).flags
        #expect(flags == [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn])
    }

    @Test func everyKeyHasItsOwnCodeExceptAliases() {
        let aliases: Set = ["enter", "backspace", "esc"]
        let codes = KeyCombo.keys.filter { !aliases.contains($0.key) }.map(\.value)
        #expect(Set(codes).count == codes.count)
    }
}

struct EasingTests {
    @Test(arguments: Easing.allCases)
    func everyCurveStartsAtTheStartAndEndsAtTheEnd(easing: Easing) {
        #expect(easing(1) == 1)
        #expect(easing == .snap || easing(0) == 0)
        #expect(easing(-1) == easing(0) && easing(2) == 1, "clamped")
    }

    @Test func curvesHaveTheirShape() {
        #expect(Easing.linear(0.25) == 0.25)
        #expect(Easing.easeIn(0.5) == 0.125)
        #expect(Easing.easeOut(0.5) == 0.875)
        #expect(Easing.easeInOut(0.5) == 0.5)
        #expect(Easing.easeInOut(0.25) == 0.0625)
        #expect(abs(Easing.smooth(0.5) - 0.5) < 1e-9)
        #expect(abs(Easing.smooth(0.25) - 0.1464466) < 1e-6)
        #expect(Easing.snap(0.01) == 1)
    }
}

import CoreGraphics

/// A key with its modifiers, as a tape writes it: `return`, `a`, `cmd+s`, `ctrl+shift+tab`.
///
/// Letters, digits and punctuation are the US ANSI positions: a shortcut is a position on the keyboard to macOS, and
/// the tape says what the app should receive.
public struct KeyCombo: Equatable, Sendable, CustomStringConvertible {
    public var keyCode: CGKeyCode
    public var modifiers: Modifiers
    /// The name as the tape wrote it, normalised: `cmd+shift+z`.
    public var description: String

    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
        public static let function = Modifiers(rawValue: 16)

        public var flags: CGEventFlags {
            var flags: CGEventFlags = []
            if contains(.command) { flags.insert(.maskCommand) }
            if contains(.shift) { flags.insert(.maskShift) }
            if contains(.option) { flags.insert(.maskAlternate) }
            if contains(.control) { flags.insert(.maskControl) }
            if contains(.function) { flags.insert(.maskSecondaryFn) }
            return flags
        }
    }

    /// nil for an unknown key or modifier, a repeated modifier, or a combo of modifiers only.
    public init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, let code = Self.keys[key] else { return nil }
        var modifiers: Modifiers = []
        var names: [String] = []
        for part in parts.dropLast() {
            guard let (name, modifier) = Self.modifierNames[part], !modifiers.contains(modifier) else { return nil }
            modifiers.insert(modifier)
            names.append(name)
        }
        keyCode = code
        self.modifiers = modifiers
        let order = ["ctrl", "opt", "shift", "cmd", "fn"]
        description = (names.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! } + [key])
            .joined(separator: "+")
    }

    private static let modifierNames: [String: (String, Modifiers)] = [
        "cmd": ("cmd", .command), "command": ("cmd", .command),
        "shift": ("shift", .shift),
        "opt": ("opt", .option), "option": ("opt", .option), "alt": ("opt", .option),
        "ctrl": ("ctrl", .control), "control": ("ctrl", .control),
        "fn": ("fn", .function),
    ]

    /// Virtual key codes (HIToolbox `kVK_*`).
    static let keys: [String: CGKeyCode] = {
        var keys: [String: CGKeyCode] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08,
            "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F,
            "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
            "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
            "0": 0x1D,
            "=": 0x18, "-": 0x1B, "]": 0x1E, "[": 0x21, "'": 0x27, ";": 0x29, "\\": 0x2A, ",": 0x2B, "/": 0x2C,
            ".": 0x2F, "`": 0x32,
            "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "backspace": 0x33,
            "escape": 0x35, "esc": 0x35, "forwarddelete": 0x75, "home": 0x73, "end": 0x77, "pageup": 0x74,
            "pagedown": 0x79, "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        ]
        let functionKeys: [CGKeyCode] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for (index, code) in functionKeys.enumerated() {
            keys["f\(index + 1)"] = code
        }
        return keys
    }()
}

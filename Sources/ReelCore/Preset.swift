import Foundation

/// A `.reelpreset`: settings and profiles that tapes `Import`, so a team writes its look and its profiles once. It
/// holds `Import` lines (first), `Set` lines, which are defaults a tape's own `Set` overrides, and `Profile` blocks;
/// nothing that records.
struct Preset: Equatable, Sendable {
    /// Its `Set` lines, after those of what it imports.
    var settings: [Profile.Setting] = []
    /// Its `Profile` blocks, after those of what it imports.
    var definitions: [Profile.Definition] = []
    /// Relative paths that lead out of the git root, with where they are.
    var warnings: [String] = []

    static let fileExtension = "reelpreset"

    /// A `Set` line's value as it is kept until applied: its words, or, holding a condition, as written, quotes and
    /// all, so it reads the same when it is chosen from.
    static func value(of tokens: ArraySlice<Token>) -> String {
        let conditional = tokens.contains { !$0.quoted && $0.text == "?" }
        return tokens.map { conditional ? $0.source : $0.text }.joined(separator: " ")
    }

    /// Reads the preset at `url` and, first, everything it imports. `chain` is the imports that led here: one that
    /// comes back round is an error rather than a loop.
    static func load(_ url: URL, paths: Paths, chain: [URL]) throws -> Preset {
        let name = url.lastPathComponent
        guard url.pathExtension == fileExtension else {
            throw TapeError(message: "\(name) is not a .\(fileExtension); Import reads presets, not tapes")
        }
        if chain.contains(url) {
            let loop = (chain + [url]).map(\.lastPathComponent).joined(separator: " → ")
            throw TapeError(message: "\(name) imports itself: \(loop)")
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw TapeError(message: "cannot read \(url.path)")
        }
        let directory = url.deletingLastPathComponent()
        var preset = Preset()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        var settled = false
        while index < lines.count {
            let line = index + 1
            let origin = "\(name) line \(line)"
            let fail = { (message: String) in TapeError(message: "\(origin): \(message)") }
            let tokens = try tokenize(lines[index], line: line)
            index += 1
            guard let first = tokens.first else { continue }
            let words = tokens.dropFirst().map(\.text)
            switch first.text {
            case "Import":
                guard !settled else { throw fail("Import comes first, before any Set or Profile") }
                guard words.count == 1 else { throw fail("expected Import <path to a .\(fileExtension)>") }
                let (target, warning) = try paths.resolve(words[0], against: directory, fail: fail)
                if let warning { preset.warnings.append("\(origin): \(warning)") }
                let imported = try load(target, paths: paths, chain: chain + [url])
                preset.settings += imported.settings
                preset.definitions += imported.definitions
                preset.warnings += imported.warnings
            case "Set":
                settled = true
                guard words.count >= 2 else { throw fail("expected Set <setting> <value>") }
                preset.settings.append(Profile.Setting(
                    words[0], Self.value(of: tokens.dropFirst(2)), directory: directory, origin: origin
                ))
            case "Profile":
                settled = true
                let (definition, used) = try Profile.Definition.read(
                    Array(tokens.dropFirst()), body: lines[index...], from: line, in: name, directory: directory
                )
                preset.definitions.append(definition)
                index += used
            default:
                throw fail("a preset holds Import, Set and Profile lines; \(first.text) belongs in a tape")
            }
        }
        return preset
    }
}

extension Profile.Definition {
    /// `Profile <name> [extends <base>] ["purpose"]` (its words after `Profile`), and the indented `Set` lines under
    /// it in `body`: the definition, and how many lines of `body` it took. `line` is the `Profile` line's number in
    /// `file` (nil: the tape), for errors.
    static func read(
        _ header: [Token], body: ArraySlice<String>, from line: Int, in file: String?, directory: URL
    ) throws -> (Profile.Definition, Int) {
        func at(_ number: Int) -> String {
            file.map { "\($0) line \(number)" } ?? "line \(number)"
        }
        let origin = at(line)
        let fail = { (message: String) in TapeError(message: "\(origin): \(message)") }
        let usage = "expected Profile <name> [extends <profile>] [\"what it is for\"]"
        var rest = header[...]
        guard let name = rest.popFirst(), !name.quoted else { throw fail(usage) }
        guard name.text.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil else {
            throw fail(
                "a profile's name is lowercase letters, digits and dashes, such as docs or social-2, not '\(name.text)'"
            )
        }
        guard !Profile.reservedNames.contains(name.text) else {
            throw fail("\(name.text) is an Output's type; give the profile another name")
        }
        var extends: String?
        if rest.first?.quoted == false, rest.first?.text == "extends" {
            rest.removeFirst()
            guard let base = rest.popFirst(), !base.quoted else { throw fail(usage) }
            extends = base.text
        }
        let purpose = rest.first?.quoted == true ? rest.popFirst()?.text : nil
        guard rest.isEmpty else { throw fail(usage) }

        // The block: the indented lines after it, blank ones among them included; it ends at the first line that is
        // not indented.
        var settings: [Profile.Setting] = []
        var used = 0
        for (offset, text) in body.enumerated() {
            let number = line + offset + 1
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                used = offset + 1
                continue
            }
            guard text.first?.isWhitespace == true else { break }
            used = offset + 1
            let where_ = at(number)
            let tokens = try tokenize(text, line: number)
            guard let first = tokens.first else { continue }
            let words = tokens.dropFirst().map(\.text)
            guard first.text == "Set", words.count >= 2 else {
                throw TapeError(message: "\(where_): a profile holds indented Set <setting> <value> lines")
            }
            if Profile.recordingSettings.contains(words[0]) {
                throw TapeError(
                    message: "\(where_): \(words[0]) is fixed when recording, and one take serves every profile; "
                        + "set it outside the profile"
                )
            }
            if words[0] == "Profiles" {
                throw TapeError(message: "\(where_): a profile cannot choose profiles; Set Profiles outside it")
            }
            settings.append(Profile.Setting(
                words[0], Preset.value(of: tokens.dropFirst(2)), directory: directory, origin: where_
            ))
        }
        // Blank lines after the last setting belong to what follows.
        while used > 0, body[body.startIndex + used - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            used -= 1
        }
        guard !settings.isEmpty || extends != nil else {
            throw fail("Profile \(name.text) sets nothing; indent its Set lines under it")
        }
        return (
            Profile.Definition(name: name.text, extends: extends, purpose: purpose, settings: settings, origin: origin),
            used
        )
    }
}

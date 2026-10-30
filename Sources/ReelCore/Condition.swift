import Foundation

/// A value that differs by profile or by Output type: `Set Quality social|feed ? 70 : github ? 50 : 65`, read left
/// to right, the first condition that holds choosing its value, the last value for when none does (or no profile is
/// rendering). One profile renders at a time, so a condition inside a chosen value could never matter: a chain is all
/// there is.
enum Condition {
    /// What may be a condition's name besides a profile's: an Output's type.
    static let formats = Set(Output.Format.allCases.map(\.rawValue))

    /// The tokens `tokens` come to for `profile` and `format`, or `tokens` themselves when they hold no `?`. Every
    /// name a condition tests is added to `names`, to be checked once every profile is known.
    static func choose(
        _ tokens: [Token], profile: String?, format: Output.Format?, names: inout [String],
        fail: (String) -> TapeError
    ) throws -> [Token] {
        func bare(_ text: String) -> (Token) -> Bool {
            { !$0.quoted && $0.text == text }
        }
        guard tokens.contains(where: bare("?")) else { return tokens }
        let usage = "expected <profile> ? <value> : <value>, such as social ? 70 : 60"
        let segments = tokens.split(omittingEmptySubsequences: false, whereSeparator: bare(":"))
        var chosen: [Token]?
        for (index, segment) in segments.enumerated() {
            let marks = segment.filter(bare("?")).count
            if index == segments.count - 1 {
                guard marks == 0
                else { throw fail("a condition needs a : and a value for when it does not hold; \(usage)") }
                guard !segment.isEmpty else { throw fail("nothing after the last :; \(usage)") }
                return chosen ?? Array(segment)
            }
            guard marks > 0 else { throw fail(usage) }
            guard marks == 1 else {
                throw fail(
                    "a condition inside a ? value can never matter, since one profile renders at a time; "
                        + "chain them instead: github ? 50 : social ? 70 : 65"
                )
            }
            let question = segment.firstIndex(where: bare("?"))!
            let condition = segment[segment.startIndex ..< question]
            let value = segment[segment.index(after: question)...]
            guard condition.count == 1, let test = condition.first, !test.quoted else {
                throw fail("a condition is a profile's name, or names joined by |, such as social|feed; \(usage)")
            }
            guard !value.isEmpty else { throw fail("nothing between ? and :; \(usage)") }
            let tested = test.text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard !tested.contains(where: \.isEmpty) else { throw fail("'\(test.text)' names nothing between its |") }
            names += tested
            if chosen == nil, tested.contains(where: { $0 == profile || $0 == format?.rawValue }) {
                chosen = Array(value)
            }
        }
        return chosen ?? []
    }

    /// A line of `:` and what follows continues the one before it, so a long chain can line up:
    ///
    ///     Caption github ? "brew install --cask mpdreamz/tap/reel"
    ///             : social ? "Follow for more"
    ///             : "Recorded with reel"
    ///
    /// The continued line keeps its number; the continuation becomes blank, so every other line keeps its own.
    static func joinContinuations(_ lines: [String]) -> [String] {
        var joined = lines
        var last: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":"), let previous = last {
                joined[previous] += " " + trimmed
                joined[index] = ""
            } else if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                last = index
            }
        }
        return joined
    }
}

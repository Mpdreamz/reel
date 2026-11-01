import Foundation

/// Two versions of a file as one, the way a unified diff shows them: every line of either, in order, each kept, added
/// or removed, with the words that changed marked where a removed line and an added one are the same line edited. A
/// code screen shows it in an editor of its own (`Diff`): reel works it out itself, so a diff is the same every time.
public struct CodeDiff: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case kept, added, removed
    }

    public struct Row: Equatable, Sendable {
        public var text: String
        public var kind: Kind
        /// Its number in the new file; nil for a removed line.
        public var number: Int?
        /// The columns that changed (0-based, end exclusive), in a line edited rather than replaced.
        public var words: [Range<Int>]
    }

    public var rows: [Row]

    /// Where each run of changes starts: the row (0-based) of its first changed line.
    public var hunks: [Int] {
        rows.indices.filter { rows[$0].kind != .kept && ($0 == 0 || rows[$0 - 1].kind == .kept) }
    }

    public var added: Int {
        rows.count(where: { $0.kind == .added })
    }

    public var removed: Int {
        rows.count(where: { $0.kind == .removed })
    }

    /// Lines removed and added in one place are paired up as edits when this much of them is the same.
    static let alike = 0.4

    public init(before: String, after: String) {
        let old = Self.lines(before), new = Self.lines(after)
        let difference = new.difference(from: old)
        var gone = Set<Int>(), came = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): gone.insert(offset)
            case let .insert(offset, _, _): came.insert(offset)
            }
        }
        var rows: [Row] = []
        var i = 0, j = 0
        // Removals before insertions where they meet, as a unified diff has them; then each such block's lines are
        // paired up as edits where they are alike.
        while i < old.count || j < new.count {
            if i < old.count, gone.contains(i) {
                var removed: [Row] = [], added: [Row] = []
                while i < old.count, gone.contains(i) {
                    removed.append(Row(text: old[i], kind: .removed, number: nil, words: []))
                    i += 1
                }
                while j < new.count, came.contains(j) {
                    added.append(Row(text: new[j], kind: .added, number: j + 1, words: []))
                    j += 1
                }
                Self.pair(&removed, &added)
                rows += removed + added
            } else if j < new.count, came.contains(j) {
                rows.append(Row(text: new[j], kind: .added, number: j + 1, words: []))
                j += 1
            } else {
                rows.append(Row(text: new[j], kind: .kept, number: j + 1, words: []))
                i += 1
                j += 1
            }
        }
        self.rows = rows
    }

    static func lines(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Marks the words that changed in each removed line and the added line in the same place, when they are alike.
    static func pair(_ removed: inout [Row], _ added: inout [Row]) {
        for k in 0 ..< min(removed.count, added.count) {
            let a = tokens(removed[k].text), b = tokens(added[k].text)
            let change = b.difference(from: a)
            var dropped = Set<Int>(), put = Set<Int>()
            for step in change {
                switch step {
                case let .remove(offset, _, _): dropped.insert(offset)
                case let .insert(offset, _, _): put.insert(offset)
                }
            }
            let same = a.indices.filter { !dropped.contains($0) && !a[$0].trimmingCharacters(in: .whitespaces).isEmpty }
            let meaningful = max(1, a.count(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }))
            guard Double(same.count) / Double(meaningful) >= alike else { continue }
            removed[k].words = columns(a, marked: dropped)
            added[k].words = columns(b, marked: put)
        }
    }

    /// A line as words, runs of space, and single other characters: what changes within it is told in these.
    static func tokens(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var kind = 0
        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }
        for character in line {
            let next = character.isLetter || character.isNumber || character == "_" ? 1 : character == " " ? 2 : 3
            if next != kind || next == 3 { flush() }
            kind = next
            current.append(character)
        }
        flush()
        return tokens
    }

    /// The column ranges the `marked` tokens cover, joined where they touch or only a space is between them.
    static func columns(_ tokens: [String], marked: Set<Int>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var column = 0
        for (index, token) in tokens.enumerated() {
            let width = token.count
            if marked.contains(index), token.trimmingCharacters(in: .whitespaces).isEmpty == false {
                if let last = ranges.last, column - last.upperBound <= 1 {
                    ranges[ranges.count - 1] = last.lowerBound ..< column + width
                } else {
                    ranges.append(column ..< column + width)
                }
            }
            column += width
        }
        return ranges
    }
}

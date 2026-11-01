import CoreGraphics
import Foundation

/// How the tracks share the canvas: `term | app` side by side, `term / app` one above the other, grouped with
/// parentheses, `(term / script) | app`. A part may carry its share of the cut, `term 40% | app`; the rest share what
/// is left by their own sizes.
public indirect enum Layout: Equatable, Sendable, CustomStringConvertible {
    case track(String)
    case cut(Cut, [Part])

    public enum Cut: String, Equatable, Sendable {
        case across = "|"
        case down = "/"
    }

    public struct Part: Equatable, Sendable {
        public var arrangement: Layout
        /// Of the cut, 0…1; nil shares what is left.
        public var share: Double?
    }

    /// Every track it names, in order.
    public var names: [String] {
        switch self {
        case let .track(name): [name]
        case let .cut(_, parts): parts.flatMap(\.arrangement.names)
        }
    }

    public var description: String {
        switch self {
        case let .track(name): name
        case let .cut(cut, parts):
            parts.map { part in
                var text = part.arrangement.description
                if case .cut = part.arrangement { text = "(\(text))" }
                if let share = part.share { text += " \(Self.percent(share))" }
                return text
            }.joined(separator: " \(cut.rawValue) ")
        }
    }

    static func percent(_ share: Double) -> String {
        let value = (share * 1000).rounded() / 10
        return value == value.rounded() ? "\(Int(value))%" : "\(value)%"
    }

    /// Side by side turned into one above the other: what a tall canvas does to an arrangement written for a wide one.
    var stacked: Layout {
        switch self {
        case .track: self
        case let .cut(_, parts):
            .cut(.down, parts.map { Part(arrangement: $0.arrangement.stacked, share: $0.share) })
        }
    }

    /// Without the tracks not in `kept`; a cut left with one part is that part. Nil when nothing is left.
    func keeping(_ kept: Set<String>) -> Layout? {
        switch self {
        case let .track(name):
            return kept.contains(name) ? self : nil
        case let .cut(cut, parts):
            let left = parts.compactMap { part in
                part.arrangement.keeping(kept).map { Part(arrangement: $0, share: part.share) }
            }
            if left.isEmpty { return nil }
            if left.count == 1 { return left[0].arrangement }
            return .cut(cut, left)
        }
    }

    /// With the top cut's parts given these shares, in order; nil clears them.
    func split(_ shares: [Double]?) -> Layout {
        guard case let .cut(cut, parts) = self else { return self }
        return .cut(cut, parts.enumerated().map { index, part in
            Part(arrangement: part.arrangement, share: shares.flatMap { index < $0.count ? $0[index] : nil })
        })
    }

    /// The track, and every group it is in, larger in its cut; the others in those cuts share what is left.
    func spotlighting(_ name: String) -> Layout {
        guard case let .cut(cut, parts) = self, parts.contains(where: { $0.arrangement.names.contains(name) })
        else { return self }
        return .cut(cut, parts.map { part in
            part.arrangement.names.contains(name)
                ? Part(arrangement: part.arrangement.spotlighting(name), share: Layout.spotlight)
                : Part(arrangement: part.arrangement, share: nil)
        })
    }

    /// A spotlit part's share of its cut.
    static let spotlight = 0.7

    /// Reads `(term / script) | app`, `term 40% | app`; `fail` says what is wrong.
    static func parse(_ text: String, fail: (String) -> TapeError) throws -> Layout {
        var scanner = Scanner(text: Array(text))
        let arrangement = try scanner.expression(fail: fail)
        guard scanner.atEnd() else { throw fail("'\(scanner.rest)' does not belong in a layout; \(usage)") }
        return arrangement
    }

    static let usage = "write track names with | for side by side and / for one above the other, such as "
        + "(term / script) | app"

    private struct Scanner {
        var text: [Character]
        var at = 0

        mutating func atEnd() -> Bool {
            space()
            return at >= text.count
        }

        var rest: String {
            String(text[min(at, text.count)...])
        }

        mutating func space() {
            while at < text.count, text[at].isWhitespace {
                at += 1
            }
        }

        mutating func peek() -> Character? {
            space()
            return at < text.count ? text[at] : nil
        }

        mutating func expression(fail: (String) -> TapeError) throws -> Layout {
            var parts = try [part(fail: fail)]
            var cut: Layout.Cut?
            while let c = peek(), let next = Layout.Cut(rawValue: String(c)) {
                if let cut, cut != next {
                    throw fail("a layout mixes | and / only in groups: write (a | b) / c or a | (b / c)")
                }
                cut = next
                at += 1
                try parts.append(part(fail: fail))
            }
            guard let cut else {
                if parts[0].share != nil { throw fail("a share belongs to a part of a cut, such as term 40% | app") }
                return parts[0].arrangement
            }
            let shared = parts.compactMap(\.share)
            let total = shared.reduce(0, +)
            if total > 1.0001 || (shared.count == parts.count && abs(total - 1) > 0.0001) {
                throw fail("the shares in a cut add up to \(Layout.percent(total)); "
                    + (total > 1.0001 ? "they make at most 100%" : "when every part has one they make 100%"))
            }
            return .cut(cut, parts)
        }

        mutating func part(fail: (String) -> TapeError) throws -> Part {
            let arrangement: Layout
            if peek() == "(" {
                at += 1
                arrangement = try expression(fail: fail)
                guard peek() == ")" else { throw fail("a ( in the layout is not closed") }
                at += 1
            } else {
                let start = at
                while at < text.count, text[at].isLetter || text[at].isNumber || text[at] == "-" || text[at] == "_" {
                    at += 1
                }
                guard at > start, text[start].isLetter else {
                    throw fail(at < text.count ? "'\(rest)' does not belong in a layout; \(usage)"
                        : "the layout ends early; \(usage)")
                }
                arrangement = .track(String(text[start ..< at]))
            }
            var share: Double?
            space()
            let start = at
            while at < text.count, text[at].isNumber || text[at] == "." {
                at += 1
            }
            if at > start {
                guard at < text.count, text[at] == "%", let value = Double(String(text[start ..< at])),
                      value > 0, value < 100
                else { throw fail("a share is a percentage above 0% and below 100%, such as term 40% | app") }
                at += 1
                share = value / 100
            }
            return Part(arrangement: arrangement, share: share)
        }
    }
}

/// A move of the director's camera over the tracks, at render time.
public enum Move: Equatable, Sendable {
    /// `Layout <arrangement>`: the tracks arranged anew. Ends a fullscreen or a picture-in-picture.
    case layout(Layout)
    /// `Split 40%`, `Split 30% 50%`: the top cut's parts get these shares, in order; `Split off` (nil) gives them back
    /// their own.
    case split([Double]?)
    /// `Spotlight <name>`: that track larger, the others smaller; `Spotlight off` (nil).
    case spotlight(String?)
    /// `Fullscreen <name>`: that track alone, as large as the canvas holds; `Fullscreen off` (nil).
    case fullscreen(String?)
    /// `Pip <name> [over <name>] [corner]`: that track small in a corner over the rest (or over one); `Pip off` (nil).
    case pip(Pip?)

    /// The track names it mentions.
    var names: [String] {
        switch self {
        case let .layout(arrangement): arrangement.names
        case .split: []
        case let .spotlight(name), let .fullscreen(name): name.map { [$0] } ?? []
        case let .pip(pip): pip.map { [$0.name] + ($0.over.map { [$0] } ?? []) } ?? []
        }
    }
}

public struct Pip: Equatable, Sendable {
    public var name: String
    public var over: String?
    public var corner: Corner

    public enum Corner: String, Equatable, Sendable, CaseIterable {
        case topLeft = "top-left"
        case topRight = "top-right"
        case bottomLeft = "bottom-left"
        case bottomRight = "bottom-right"
    }
}

/// Where the tracks are on the canvas, and how they move between arrangements as the director says.
struct TrackLayout: Sendable {
    var canvas: CGSize
    /// The canvas less its padding: what the tracks are laid out in.
    var room: CGRect
    var names: [String]
    /// Each track's recording, in pixels, and its pixels a point.
    var sizes: [CGSize]
    var scales: [Double]
    /// A tall canvas stacks what is written side by side.
    var tall: Bool

    /// Where one track is drawn: its window, how opaque, and above which others (higher on top).
    struct Placement: Equatable, Sendable {
        /// Nil while it is not shown and was never placed.
        var frame: CGRect?
        var alpha: Double
        var z: Int
    }

    /// What the director has said so far, and which tracks have started.
    struct Stage: Equatable, Sendable {
        var arrangement: Layout
        var split: [Double]?
        var spotlight: String?
        var fullscreen: String?
        var pip: Pip?
        var present: Set<String>

        mutating func apply(_ move: Move) {
            switch move {
            case let .layout(next):
                arrangement = next
                fullscreen = nil
                pip = nil
                if let name = spotlight, !next.names.contains(name) { spotlight = nil }
            case let .split(shares): split = shares
            case let .spotlight(name): spotlight = name
            case let .fullscreen(name):
                fullscreen = name
                if name != nil { pip = nil }
            case let .pip(next):
                pip = next
                if next != nil { fullscreen = nil }
            }
        }
    }

    /// The gap between two tracks, as a share of the cut's other side.
    static let gap = 0.04
    /// A picture-in-picture's largest share of what it is over, each way, and its distance from the corner.
    static let pipShare = 0.34
    static let pipInset = 0.03

    /// Laid out for `arrangement` (every track side by side when nil), the canvas the smallest of `shape` that holds
    /// it as `Framing` would a recording of that size.
    static func make(
        names: [String], sizes: [CGSize], scales: [Double], shape: Output.Shape, padding: Double,
        arrangement: Layout? = nil
    ) -> TrackLayout {
        let tall = switch shape {
        case let .aspect(w, h): w < h
        case let .size(w, h): w < h
        }
        var layout = TrackLayout(
            canvas: .zero, room: .zero, names: names, sizes: sizes, scales: scales, tall: tall
        )
        let start = layout.oriented(arrangement ?? layout.everyTrack)
        let framing = Framing.make(
            recording: layout.natural(start), scale: 1, shape: shape, padding: padding, background: .standard
        )
        return layout.resized(to: framing.canvas, padding: padding)
    }

    /// The same layout on `canvas`, one of the same shape: every window where it was, in proportion.
    func resized(to canvas: CGSize, padding: Double) -> TrackLayout {
        var layout = self
        layout.canvas = canvas
        let pad = padding * min(canvas.width, canvas.height)
        layout.room = CGRect(origin: .zero, size: canvas).insetBy(dx: pad, dy: pad)
        return layout
    }

    var everyTrack: Layout {
        names.count == 1 ? .track(names[0]) : .cut(.across, names.map { .init(arrangement: .track($0), share: nil) })
    }

    func oriented(_ arrangement: Layout) -> Layout {
        tall ? arrangement.stacked : arrangement
    }

    /// Each track's window for a stage, in the order of `names`.
    func placements(_ stage: Stage) -> [Placement] {
        var shown = stage.arrangement.split(stage.split)
        if let name = stage.spotlight { shown = shown.spotlighting(name) }
        let windows: [String: CGRect] = shown.keeping(stage.present).map { arrange(oriented($0), in: room) } ?? [:]
        if let name = stage.fullscreen, stage.present.contains(name), let index = names.firstIndex(of: name) {
            // The others fade where the layout has them, under it.
            let full = fit(sizes[index], in: room)
            return names.map { track in
                track == name ? Placement(frame: full, alpha: 1, z: 1) : Placement(
                    frame: windows[track],
                    alpha: 0,
                    z: 0
                )
            }
        }
        if let pip = stage.pip, stage.present.contains(pip.name), let index = names.firstIndex(of: pip.name) {
            var base = shown
            if let over = pip.over, stage.present.contains(over) {
                base = .track(over)
            }
            let kept = stage.present.subtracting([pip.name])
            let laid = base.keeping(kept).map { arrange(oriented($0), in: room) } ?? [:]
            var under = laid.values.reduce(CGRect.null) { $0.union($1) }
            if under.isNull { under = room }
            let box = CGRect(
                x: 0, y: 0, width: under.width * Self.pipShare, height: under.height * Self.pipShare
            )
            let size = fit(sizes[index], in: box).size
            let inset = Self.pipInset * min(under.width, under.height)
            let left = pip.corner == .topLeft || pip.corner == .bottomLeft
            let top = pip.corner == .topLeft || pip.corner == .topRight
            let frame = CGRect(
                x: left ? under.minX + inset : under.maxX - inset - size.width,
                y: top ? under.minY + inset : under.maxY - inset - size.height,
                width: size.width, height: size.height
            )
            // What the picture is not over fades where the layout has it.
            return names.map { track in
                if track == pip.name { return Placement(frame: frame, alpha: 1, z: 2) }
                return laid[track].map { Placement(frame: $0, alpha: 1, z: 0) }
                    ?? Placement(frame: windows[track], alpha: 0, z: 0)
            }
        }
        return names.map { track in
            windows[track].map { Placement(frame: $0, alpha: 1, z: 0) } ?? Placement(frame: nil, alpha: 0, z: 0)
        }
    }

    /// Each named track's window in `rect`: a cut with shares fills the rect by them; one without is laid out at its
    /// own shape, as large as the rect holds.
    func arrange(_ arrangement: Layout, in rect: CGRect) -> [String: CGRect] {
        switch arrangement {
        case let .track(name):
            guard let index = names.firstIndex(of: name) else { return [:] }
            return [name: fit(sizes[index], in: rect)]
        case let .cut(cut, parts):
            let across = cut == .across
            let shared = parts.contains { $0.share != nil }
            let area = shared ? rect : fit(natural(arrangement), in: rect)
            let gap = Self.gap * (across ? area.height : area.width)
            let length = (across ? area.width : area.height) - gap * Double(parts.count - 1)
            // Each part's length at the cut's other side, for those that share what is left.
            let own = parts.map { part -> Double in
                let size = natural(part.arrangement)
                return across ? size.width / size.height : size.height / size.width
            }
            let given = parts.compactMap(\.share).reduce(0, +)
            let free = parts.indices.filter { parts[$0].share == nil }
            let ownTotal = free.map { own[$0] }.reduce(0, +)
            let shares = parts.indices.map { index -> Double in
                if let share = parts[index].share { return given > 1 ? share / given : share }
                return ownTotal > 0 ? max(0, 1 - given) * own[index] / ownTotal : 0
            }
            var windows: [String: CGRect] = [:]
            var at = across ? area.minX : area.minY
            for (part, share) in zip(parts, shares) {
                let size = length * share
                let cell = across
                    ? CGRect(x: at, y: area.minY, width: size, height: area.height)
                    : CGRect(x: area.minX, y: at, width: area.width, height: size)
                windows.merge(arrange(part.arrangement, in: cell)) { first, _ in first }
                at += size + gap
            }
            return windows
        }
    }

    /// Its size at its own shape, in pixels: side by side at the tallest part's height, stacked at the widest's width,
    /// with the gaps between them.
    func natural(_ arrangement: Layout) -> CGSize {
        switch arrangement {
        case let .track(name):
            return names.firstIndex(of: name).map { sizes[$0] } ?? CGSize(width: 1, height: 1)
        case let .cut(cut, parts):
            let each = parts.map { natural($0.arrangement) }
            let gaps = Double(parts.count - 1) * Self.gap
            if cut == .across {
                let height = each.map(\.height).max() ?? 1
                let width = each.map { $0.width * height / $0.height }.reduce(0, +) + gaps * height
                return CGSize(width: width, height: height)
            }
            let width = each.map(\.width).max() ?? 1
            let height = each.map { $0.height * width / $0.width }.reduce(0, +) + gaps * width
            return CGSize(width: width, height: height)
        }
    }

    /// `size`, as large as `rect` holds it, centred in it.
    func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
            width: fitted.width, height: fitted.height
        )
    }

    /// A track's window corner, in canvas pixels, at the size it is drawn.
    func corner(_ index: Int, at frame: CGRect) -> Double {
        Framing.windowCorner * scales[index] * frame.width / sizes[index].width
    }
}

/// The director's camera over the movie: from what it starts with, each move (and each track that starts late) easing
/// from where everything was to where it goes.
struct Direction: Sendable {
    var layout: TrackLayout
    var shots: [Shot]

    struct Shot: Sendable {
        var start: Double
        var easing: Easing
        var seconds: Double
        var from: [TrackLayout.Placement]
        var to: [TrackLayout.Placement]
    }

    /// A move's easing and length unless it says.
    static let standard = Transition(easing: .easeInOut, duration: .milliseconds(600))
    /// A track that starts within this many seconds of the rest is there from the first frame; a later one grows in
    /// when it starts.
    static let together = 0.5

    /// - Parameters:
    ///   - starts: each track's first frame, in seconds on the movie's clock.
    ///   - moves: the director's moves, each at its time, in order.
    static func make(
        layout: TrackLayout, start: Layout?, starts: [Double],
        moves: [(at: Double, move: Move, transition: Transition?)]
    ) -> Direction {
        var stage = TrackLayout.Stage(
            arrangement: start ?? layout.everyTrack, split: nil, spotlight: nil, fullscreen: nil, pip: nil,
            present: Set(zip(layout.names, starts).filter { $0.1 <= together }.map(\.0))
        )
        var direction = Direction(layout: layout, shots: [])
        let first = layout.placements(stage)
        direction.shots.append(Shot(start: -.infinity, easing: .snap, seconds: 0, from: first, to: first))
        // Moves and late starts, in time; a start before a move at the same moment.
        var changes: [(at: Double, change: (inout TrackLayout.Stage) -> Void, transition: Transition?)] = []
        for (name, at) in zip(layout.names, starts) where at > together {
            changes.append((at, { $0.present.insert(name) }, nil))
        }
        for move in moves {
            changes.append((move.at, { $0.apply(move.move) }, move.transition))
        }
        for change in changes.enumerated().sorted(by: { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) })
            .map(\.element)
        {
            change.change(&stage)
            let (easing, seconds) = (change.transition ?? standard).over(standard)
            let from = direction.placements(at: change.at)
            direction.shots.append(Shot(
                start: change.at, easing: easing, seconds: seconds, from: from,
                to: layout.placements(stage)
            ))
        }
        return direction
    }

    /// Where every track is at `time`.
    func placements(at time: Double) -> [TrackLayout.Placement] {
        guard let shot = shots.last(where: { $0.start <= time }) ?? shots.first else { return [] }
        let progress = shot.seconds > 0 ? shot.easing((time - shot.start) / shot.seconds) : 1
        return zip(shot.from, shot.to).map { from, to in
            Self.between(from, to, progress)
        }
    }

    /// Part of the way from one placement to another: a track that appears grows from its middle, one that goes
    /// fades where it was.
    static func between(
        _ from: TrackLayout.Placement, _ to: TrackLayout.Placement, _ progress: Double
    ) -> TrackLayout.Placement {
        let target = to.frame ?? from.frame
        var start = from.alpha > 0 ? from.frame ?? target : target.map { grown($0, by: 0.6) }
        if from.alpha <= 0, to.alpha <= 0 { start = from.frame ?? to.frame }
        let frame: CGRect? = switch (start, target) {
        case let (a?, b?): CGRect(
                x: a.minX + (b.minX - a.minX) * progress, y: a.minY + (b.minY - a.minY) * progress,
                width: a.width + (b.width - a.width) * progress, height: a.height + (b.height - a.height) * progress
            )
        default: target ?? start
        }
        return TrackLayout.Placement(
            frame: frame, alpha: from.alpha + (to.alpha - from.alpha) * progress,
            z: progress >= 1 ? to.z : max(from.z, to.z)
        )
    }

    private static func grown(_ rect: CGRect, by scale: Double) -> CGRect {
        CGRect(
            x: rect.midX - rect.width * scale / 2, y: rect.midY - rect.height * scale / 2,
            width: rect.width * scale, height: rect.height * scale
        )
    }
}

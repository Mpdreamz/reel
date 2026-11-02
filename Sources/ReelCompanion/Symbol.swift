import AppKit

/// The reel symbol for the menu bar, drawn from the brand's small cut (design/brand/logo/svg/reel-symbol-small-*.svg:
/// a disc with four holes and a play mark, on a 64 grid), as a template image, so macOS tints it for the menu bar.
/// Rendering adds a ring that fills as the pass goes.
enum Symbol {
    static let size = NSSize(width: 18, height: 18)

    /// The symbol, `progress` (0 to 1) as a ring round it when given.
    static func image(progress: Double? = nil) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            let ring = progress != nil
            // Room for the ring: the disc shrinks inside it.
            let inset = ring ? 3.5 : 1.0
            let disc = rect.insetBy(dx: inset, dy: inset)
            let unit = disc.width / 64
            func point(_ x: Double, _ y: Double) -> NSPoint {
                NSPoint(x: disc.minX + x * unit, y: disc.minY + y * unit)
            }
            let path = NSBezierPath(ovalIn: disc.insetBy(dx: 2 * unit, dy: 2 * unit))
            for (x, y) in [(20.0, 20.0), (44, 20), (20, 44), (44, 44)] {
                path.append(NSBezierPath(ovalIn: NSRect(
                    x: disc.minX + (x - 7) * unit, y: disc.minY + (y - 7) * unit, width: 14 * unit, height: 14 * unit
                )))
            }
            let play = NSBezierPath()
            play.move(to: point(29, 26.5))
            play.line(to: point(38, 32))
            play.line(to: point(29, 37.5))
            play.close()
            path.append(play)
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            if let progress {
                let track = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                track.lineWidth = 1.5
                NSColor.black.withAlphaComponent(0.3).setStroke()
                track.stroke()
                let arc = NSBezierPath()
                let center = NSPoint(x: rect.midX, y: rect.midY)
                // Flipped: clockwise from the top.
                arc.appendArc(
                    withCenter: center, radius: rect.width / 2 - 0.75, startAngle: -90,
                    endAngle: -90 + 360 * min(1, max(0, progress)), clockwise: false
                )
                arc.lineWidth = 1.5
                NSColor.black.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

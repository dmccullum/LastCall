import AppKit

/// The menu bar glyph, 5-hour session and weekly, each in proportion to its utilization.
/// Capsules stacks two outlined capsules, session on top. Rings draws two concentric open
/// arcs, session outside. A template image, so the system colors it.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 14)

    /// Space between the capsules and the text.
    static let textSpacing: CGFloat = 4

    /// Fractions are 0 to 1; nil draws an empty capsule. With `text`, the text is drawn
    /// into the same image so the status item pads it like an icon-only item; a SwiftUI
    /// Text title gets wider insets than the icons next to it. `sessionPace` and
    /// `weeklyPace` are elapsed fractions of each window, drawn as a tick across the capsule.
    static func image(
        session: Double?,
        weekly: Double?,
        sessionPace: Double? = nil,
        weeklyPace: Double? = nil,
        text: String? = nil,
        style: MenuBarStyle = .capsules
    ) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let title = text.map { NSAttributedString(string: $0, attributes: attributes) }
        let titleSize = title?.size() ?? .zero
        // Rings is 20 by 18 pt to match the optical size of the round icons beside it.
        let glyph = style == .rings ? NSSize(width: 20, height: 18) : size
        let canvas = NSSize(
            width: glyph.width + (title == nil ? 0 : textSpacing + ceil(titleSize.width)),
            height: max(glyph.height, ceil(titleSize.height))
        )
        let image = NSImage(size: canvas, flipped: false) { _ in
            switch style {
            case .capsules:
                let height: CGFloat = 5.5
                let gap: CGFloat = 1.5
                let originY = ((canvas.height - size.height) / 2).rounded()
                let top = NSRect(x: 0.5, y: originY + 0.5 + height + gap, width: size.width - 1, height: height)
                let bottom = NSRect(x: 0.5, y: originY + 0.5, width: size.width - 1, height: height)
                draw(capsule: top, fill: session)
                draw(capsule: bottom, fill: weekly)
                if let sessionPace { draw(tick: sessionPace, across: top) }
                if let weeklyPace { draw(tick: weeklyPace, across: bottom) }
            case .rings:
                // Whole-point centre and radii so both 2 pt strokes land on pixel edges at 1x.
                // The arcs span 1.5 to 17 pt above the bottom of the 18 pt glyph, ticks to 18.
                let center = NSPoint(x: glyph.width / 2, y: ((canvas.height - glyph.height) / 2).rounded() + 7)
                draw(arc: 9, center: center, fill: session, pace: sessionPace)
                draw(arc: 5, center: center, fill: weekly, pace: weeklyPace)
                if let sessionPace { draw(tick: sessionPace, radius: 9, center: center) }
                if let weeklyPace { draw(tick: weeklyPace, radius: 5, center: center) }
            }
            title?.draw(at: NSPoint(x: glyph.width + textSpacing, y: ((canvas.height - titleSize.height) / 2).rounded()))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(capsule rect: NSRect, fill: Double?) {
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let outline = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        outline.lineWidth = 1
        outline.stroke()
        guard let fill, fill > 0 else { return }
        let inset = rect.insetBy(dx: 1.5, dy: 1.5)
        // A fill shorter than its own height would look like a dot; keep it a capsule.
        let width = max(inset.height, inset.width * min(fill, 1))
        let bar = NSRect(x: inset.minX, y: inset.minY, width: width, height: inset.height)
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
    }

    /// A 1 pt tick from the capsule's top edge to its bottom edge. Inside the outline, 1 pt
    /// is cleared on each side so the tick reads against the fill in a template image.
    private static func draw(tick fraction: Double, across rect: NSRect) {
        let outer = rect.insetBy(dx: -0.5, dy: -0.5)
        // Keep the tick off the rounded ends, where it would merge with the outline.
        let center = rect.minX + rect.width * min(max(fraction, 0), 1)
        let x = min(max(center.rounded(.down), outer.minX + 2), outer.maxX - 3)
        NSRect(x: x - 1, y: rect.minY + 0.5, width: 3, height: rect.height - 1).fill(using: .clear)
        NSColor.black.setFill()
        NSRect(x: x, y: outer.minY, width: 1, height: outer.height).fill()
    }

    // Gauge sweep in degrees, counterclockwise from +x: starts lower left, runs clockwise
    // over the top to lower right, leaving the gap at the bottom.
    private static let sweepStart: CGFloat = 210
    private static let sweepLength: CGFloat = 240

    private static func draw(arc radius: CGFloat, center: NSPoint, fill: Double?, pace: Double?) {
        func arc(_ fraction: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center, radius: radius,
                startAngle: sweepStart, endAngle: sweepStart - sweepLength * fraction, clockwise: true
            )
            path.lineWidth = 2
            path.lineCapStyle = .round
            return path
        }
        NSColor.black.withAlphaComponent(0.3).setStroke()
        arc(1).stroke()
        guard let fill, fill > 0 else { return }
        NSColor.black.setStroke()
        arc(CGFloat(min(fill, 1))).stroke()
    }

    /// A 1 pt radial tick at the pace angle, reaching 1 pt past each side of the 2 pt ring.
    /// A 3 pt wide strip under it is cleared so the tick reads against the fill.
    private static func draw(tick fraction: Double, radius: CGFloat, center: NSPoint) {
        let angle = (sweepStart - sweepLength * CGFloat(min(max(fraction, 0), 1))) * .pi / 180
        func line(width: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: center.x + (radius - 2) * cos(angle), y: center.y + (radius - 2) * sin(angle)))
            path.line(to: NSPoint(x: center.x + (radius + 2) * cos(angle), y: center.y + (radius + 2) * sin(angle)))
            path.lineWidth = width
            path.lineCapStyle = .butt
            return path
        }
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        line(width: 3).stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.black.setStroke()
        line(width: 1).stroke()
    }
}

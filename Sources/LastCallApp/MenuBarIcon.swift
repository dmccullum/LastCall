import AppKit

/// The menu bar glyph, 5-hour session and weekly, each in proportion to its utilization.
/// Capsules stacks two outlined capsules, session on top. Rings draws two concentric open
/// arcs, session outside. Ring draws one full circle for the session only. A template
/// image, so the system colors it.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 14)

    /// Rings is 20 by 18 pt and Ring 19 by 21 pt to match the optical size of the round
    /// icons beside them. Ring is as wide as its stroke, so the status item spacing matches
    /// the icons beside it; a pace tick at 3 or 9 o’clock loses its outer 1 pt.
    static func glyphSize(_ style: MenuBarStyle) -> NSSize {
        switch style {
        case .capsules: size
        case .rings: NSSize(width: 20, height: 18)
        case .ring: NSSize(width: 19, height: 21)
        }
    }

    /// Space between the capsules and the text.
    static let textSpacing: CGFloat = 4

    /// Space between the service letter and the glyph.
    static let badgeSpacing: CGFloat = 3

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
        badge: String? = nil,
        badgeInsideRings: Bool = true,
        style: MenuBarStyle = .capsules
    ) -> NSImage {
        // The service letter (before the capsules, or inside the rings): “A” for Anthropic, “O” for OpenAI.
        let mark = badge.flatMap { $0.isEmpty ? nil : $0 }.map { NSAttributedString(string: $0, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.black
        ]) }
        let markSize = mark?.size() ?? .zero
        // Before the glyph, or inside the ring when the style is Rings or Ring and `badgeInsideRings` is on.
        let inside = style.holdsLetter && badgeInsideRings
        let markWidth = mark == nil || inside ? 0 : ceil(markSize.width) + badgeSpacing
        // Ring's single circle leaves a 15 pt opening, Rings' inner ring 8 pt.
        let ringFont = NSFont.systemFont(ofSize: style == .ring ? 9.5 : 7, weight: .heavy)
        let ringMark = !inside ? nil : badge.flatMap { $0.isEmpty ? nil : $0 }.map {
            NSAttributedString(string: $0, attributes: [
                .font: ringFont,
                .foregroundColor: NSColor.black
            ])
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let title = text.map { NSAttributedString(string: $0, attributes: attributes) }
        let titleSize = title?.size() ?? .zero
        let glyph = glyphSize(style)
        let canvas = NSSize(
            width: markWidth + glyph.width + (title == nil ? 0 : textSpacing + ceil(titleSize.width)),
            height: max(glyph.height, ceil(titleSize.height))
        )
        let image = NSImage(size: canvas, flipped: false) { _ in
            if !inside {
                mark?.draw(at: NSPoint(x: 0, y: ((canvas.height - markSize.height) / 2).rounded()))
            }
            NSGraphicsContext.current?.saveGraphicsState()
            let shift = NSAffineTransform()
            shift.translateX(by: markWidth, yBy: 0)
            shift.concat()
            var ringCenter: NSPoint?
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
                draw(arc: 9, center: center, sweep: gauge, fill: session)
                draw(arc: 5, center: center, sweep: gauge, fill: weekly)
                if let sessionPace { draw(tick: sessionPace, radius: 9, center: center, sweep: gauge) }
                if let weeklyPace { draw(tick: weeklyPace, radius: 5, center: center, sweep: gauge) }
                ringCenter = center
            case .ring:
                // Half-point centre and radius, so the 2 pt stroke's edges still land on whole
                // points at 1x. The ring spans the 19 pt width and 1 to 20 pt of the 21 pt height;
                // the tick reaches 0 to 21 at 12 and 6 o’clock.
                let center = NSPoint(x: glyph.width / 2, y: ((canvas.height - glyph.height) / 2).rounded() + 10.5)
                draw(arc: 8.5, center: center, sweep: circle, fill: session)
                if let sessionPace { draw(tick: sessionPace, radius: 8.5, center: center, sweep: circle) }
                ringCenter = center
            }
            if let ringMark, let ringCenter, let context = NSGraphicsContext.current?.cgContext {
                // The letter's ink, not its line box, centred on the ring's centre, so A and O
                // both sit in the middle whatever the font's ascender and descender.
                let line = CTLineCreateWithAttributedString(ringMark)
                context.textMatrix = .identity
                context.textPosition = .zero
                let ink = CTLineGetImageBounds(line, context)
                context.textPosition = CGPoint(
                    x: ((ringCenter.x - ink.midX) * 2).rounded() / 2,
                    y: ((ringCenter.y - ink.midY) * 2).rounded() / 2
                )
                CTLineDraw(line, context)
            }
            NSGraphicsContext.current?.restoreGraphicsState()
            title?.draw(at: NSPoint(x: markWidth + glyph.width + textSpacing, y: ((canvas.height - titleSize.height) / 2).rounded()))
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

    /// Where an arc starts and how far it runs clockwise, in degrees counterclockwise from +x.
    private struct Sweep {
        let start: CGFloat
        let length: CGFloat

        func angle(_ fraction: CGFloat) -> CGFloat { start - length * fraction }
    }

    /// Rings: starts lower left, runs clockwise over the top to lower right, leaving the gap at the bottom.
    private static let gauge = Sweep(start: 210, length: 240)
    /// Ring: a full circle from 12 o’clock.
    private static let circle = Sweep(start: 90, length: 360)

    private static func draw(arc radius: CGFloat, center: NSPoint, sweep: Sweep, fill: Double?) {
        func arc(_ fraction: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: center, radius: radius,
                startAngle: sweep.start, endAngle: sweep.angle(fraction), clockwise: true
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
    private static func draw(tick fraction: Double, radius: CGFloat, center: NSPoint, sweep: Sweep) {
        let angle = sweep.angle(CGFloat(min(max(fraction, 0), 1))) * .pi / 180
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

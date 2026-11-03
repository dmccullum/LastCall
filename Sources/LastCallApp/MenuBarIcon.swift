import AppKit

/// The menu bar glyph: two stacked capsules, 5-hour on top and weekly below, each
/// outlined and filled in proportion to its utilization. A template image, so the
/// system colors it.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 14)

    /// Space between the capsules and the text.
    static let textSpacing: CGFloat = 4

    /// Fractions are 0 to 1; nil draws an empty capsule. With `text`, the text is drawn
    /// into the same image so the status item pads it like an icon-only item; a SwiftUI
    /// Text title gets wider insets than the icons next to it.
    static func image(session: Double?, weekly: Double?, text: String? = nil) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let title = text.map { NSAttributedString(string: $0, attributes: attributes) }
        let titleSize = title?.size() ?? .zero
        let canvas = NSSize(
            width: size.width + (title == nil ? 0 : textSpacing + ceil(titleSize.width)),
            height: max(size.height, ceil(titleSize.height))
        )
        let image = NSImage(size: canvas, flipped: false) { _ in
            let height: CGFloat = 5.5
            let gap: CGFloat = 1.5
            let originY = ((canvas.height - size.height) / 2).rounded()
            let top = NSRect(x: 0.5, y: originY + 0.5 + height + gap, width: size.width - 1, height: height)
            let bottom = NSRect(x: 0.5, y: originY + 0.5, width: size.width - 1, height: height)
            draw(capsule: top, fill: session)
            draw(capsule: bottom, fill: weekly)
            title?.draw(at: NSPoint(x: size.width + textSpacing, y: ((canvas.height - titleSize.height) / 2).rounded()))
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
}

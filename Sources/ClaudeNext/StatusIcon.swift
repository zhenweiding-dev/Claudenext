import AppKit

/// The radiating burst used as the menu bar glyph.
///
/// Spoke angles and lengths were measured off
/// `Claude.app/Contents/Resources/TrayIconTemplate@3x.png`; the radii and
/// thickness were then fitted against that same bitmap, reaching 82.7%
/// intersection-over-union. The real mark is deliberately irregular — twelve
/// spokes spaced anywhere from 18° to 39° apart, tips varying by ~12% — so
/// these are the measured values rather than a clean 30° step.
enum StatusIcon {
    /// (degrees counter-clockwise from +x, tip length as a fraction of the outer radius)
    private static let spokes: [(angle: Double, reach: Double)] = [
        (7.8, 0.90), (46.8, 0.91), (81.3, 0.91), (117.8, 1.02),
        (148.3, 0.98), (182.0, 0.95), (214.4, 0.92), (238.8, 0.97),
        (267.5, 0.95), (298.0, 0.94), (316.6, 0.96), (345.1, 0.92),
    ]

    private static let outerFraction = 0.66
    private static let coreFraction = 0.41
    private static let widthFraction = 4.5 / 36.0
    /// The mark does not sit dead centre in its own canvas.
    private static let offsetX = 0.8 / 36.0
    private static let offsetY = 0.5 / 36.0

    /// Always a plain template spark, so it takes the menu bar's own colour in
    /// both appearances. A pending request is signalled by the count beside it
    /// and by the button pulsing, not by recolouring the glyph.
    static func image() -> NSImage {
        // The shipped template is a 24pt canvas; anything smaller renders the
        // glyph visibly punier than the real menu bar icon sitting next to it.
        let side: CGFloat = 24
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }

            let half = rect.width / 2
            let center = CGPoint(x: rect.midX + half * offsetX,
                                 y: rect.midY + half * offsetY)
            let outer = half * outerFraction
            let inner = outer * coreFraction
            let thickness = half * widthFraction

            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(thickness)
            context.setLineCap(.round)

            // Stroked one at a time: merging them into a single path and
            // filling it makes the inner contours cancel out at the hub.
            for spoke in spokes {
                let radians = spoke.angle * .pi / 180
                let dx = cos(radians), dy = sin(radians)
                context.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
                context.addLine(to: CGPoint(x: center.x + dx * outer * spoke.reach,
                                            y: center.y + dy * outer * spoke.reach))
                context.strokePath()
            }
            context.fillEllipse(in: CGRect(x: center.x - inner, y: center.y - inner,
                                           width: inner * 2, height: inner * 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// `--accent-brand: 15 63.1% 59.6%` from the Claude app's own token set,
    /// which resolves to #D97757.
    static let accentColor = NSColor(srgbRed: 0xD9 / 255.0,
                                     green: 0x77 / 255.0,
                                     blue: 0x57 / 255.0,
                                     alpha: 1)
}

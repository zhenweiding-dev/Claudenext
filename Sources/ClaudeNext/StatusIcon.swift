import AppKit

/// The radiating spark used as the menu bar glyph.
enum StatusIcon {
    static func image(active: Bool) -> NSImage {
        let size = NSSize(width: 17, height: 17)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outer = rect.width * 0.47
            let inner = rect.width * 0.11
            let thickness = rect.width * 0.115

            let spokes = 8
            let path = NSBezierPath()
            for i in 0..<spokes {
                let angle = (Double(i) / Double(spokes)) * 2 * .pi + .pi / 2
                // Longer spokes on the cardinal axes, like the Claude mark.
                let length = i % 2 == 0 ? outer : outer * 0.78
                let start = CGPoint(x: center.x + cos(angle) * inner,
                                    y: center.y + sin(angle) * inner)
                let end = CGPoint(x: center.x + cos(angle) * length,
                                  y: center.y + sin(angle) * length)
                let spoke = NSBezierPath()
                spoke.move(to: start)
                spoke.line(to: end)
                spoke.lineWidth = thickness
                spoke.lineCapStyle = .round
                path.append(spoke.copy(strokingWith: thickness))
            }

            (active ? accentColor : NSColor.black).setFill()
            path.fill()
            return true
        }
        image.isTemplate = !active
        return image
    }

    static let accentColor = NSColor(srgbRed: 0xD9 / 255.0,
                                           green: 0x77 / 255.0,
                                           blue: 0x57 / 255.0,
                                           alpha: 1)
}

private extension NSBezierPath {
    /// AppKit has no `copy(strokingWith:)`, so flatten the stroke by hand.
    func copy(strokingWith width: CGFloat) -> NSBezierPath {
        let cg = CGPath(__byStroking: self.cgPath,
                        transform: nil,
                        lineWidth: width,
                        lineCap: .round,
                        lineJoin: .round,
                        miterLimit: 10)
        guard let cg else { return self }
        return NSBezierPath(cgPath: cg)
    }
}

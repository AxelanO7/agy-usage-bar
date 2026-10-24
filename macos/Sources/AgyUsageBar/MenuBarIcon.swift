import AppKit

enum MenuBarIcon {
    /// Small usage ring for the menu bar: faint track plus a colored arc that starts at 12 o'clock.
    /// The drawing handler runs on every draw, so the track follows light/dark menu bars.
    static func ring(used: Double, color: NSColor, size: CGFloat = 15) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lineWidth: CGFloat = 2.4
            let radius = (rect.width - lineWidth) / 2 - 0.5
            let center = NSPoint(x: rect.midX, y: rect.midY)

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.30).setStroke()
            track.stroke()

            if used > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * CGFloat(min(used, 1)), clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }
}

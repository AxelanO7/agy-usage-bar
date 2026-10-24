// Draws the app icon (ring gauge on a graphite tile) and writes PNGs for the macOS iconset and the Windows ico.
//   swift tools/make_icons.swift <output-dir>
// Then: iconutil -c icns <output-dir>/AppIcon.iconset  and  python3 tools/png2ico.py ...  (see tools/build_icons.sh)
import AppKit

func gradientColor(_ t: CGFloat) -> NSColor {
    // green -> amber, the same two status colors the app uses
    let a = (r: 0.196, g: 0.843, b: 0.294), b = (r: 1.0, g: 0.624, b: 0.039)
    return NSColor(srgbRed: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t, alpha: 1)
}

func render(size: Int, padded: Bool) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let art = padded ? s * 0.8047 : s            // macOS icons keep ~10% padding around the tile
    let origin = (s - art) / 2
    let tile = NSRect(x: origin, y: origin, width: art, height: art)
    let radius = art * 0.2237
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    if padded {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = s * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
        shadow.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGradient(starting: NSColor(srgbRed: 0.205, green: 0.210, blue: 0.225, alpha: 1),
               ending: NSColor(srgbRed: 0.075, green: 0.078, blue: 0.090, alpha: 1))!.draw(in: path, angle: -90)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    let inner = NSBezierPath(roundedRect: tile.insetBy(dx: art * 0.004, dy: art * 0.004), xRadius: radius, yRadius: radius)
    inner.lineWidth = max(1, art * 0.006)
    inner.stroke()

    let center = NSPoint(x: s / 2, y: s / 2)
    let ringR = art * 0.29
    let lineW = art * 0.112
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: ringR, startAngle: 0, endAngle: 360)
    track.lineWidth = lineW
    NSColor.white.withAlphaComponent(0.13).setStroke()
    track.stroke()

    let sweep: CGFloat = 262          // about 73% of the circle
    let steps = 130
    for i in 0..<steps {
        let a0 = 90 - sweep * CGFloat(i) / CGFloat(steps)
        let a1 = 90 - sweep * CGFloat(i + 1) / CGFloat(steps) - 0.6
        let seg = NSBezierPath()
        seg.appendArc(withCenter: center, radius: ringR, startAngle: a0, endAngle: a1, clockwise: true)
        seg.lineWidth = lineW
        seg.lineCapStyle = .butt
        gradientColor(CGFloat(i) / CGFloat(steps - 1)).setStroke()
        seg.stroke()
    }
    func cap(_ angle: CGFloat, _ color: NSColor) {
        let rad = angle * .pi / 180
        let p = NSPoint(x: center.x + ringR * cos(rad), y: center.y + ringR * sin(rad))
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - lineW / 2, y: p.y - lineW / 2, width: lineW, height: lineW)).fill()
    }
    cap(90, gradientColor(0))
    cap(90 - sweep, gradientColor(1))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try render(size: px, padded: true).write(to: iconset.appendingPathComponent("\(name).png"))
}
for px in [16, 24, 32, 48, 64, 128, 256] {
    try render(size: px, padded: false).write(to: out.appendingPathComponent("win-\(px).png"))
}
try render(size: 1024, padded: true).write(to: out.appendingPathComponent("icon-1024.png"))
print("icons -> \(out.path)")

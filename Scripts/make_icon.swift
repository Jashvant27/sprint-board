import AppKit

// Usage: swift Scripts/make_icon.swift <AppIcon.appiconset dir> [preview.png]
// Draws the Sprint Board icon (Design/icon-reference.jpg reinterpreted in Apple's flat style:
// a soft two-tone rounded square, three columns of small cards, an hourglass in the corner) with
// CoreGraphics at every macOS icon size and writes Contents.json. No bitmap source: everything is
// vector, in 1024-point units, scaled per size.
let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: make_icon.swift <AppIcon.appiconset dir> [preview.png]") }
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

/// Draws in a 1024 × 1024 top-down coordinate space (y grows downwards, like the reference).
func drawIcon(in ctx: CGContext, size: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: size / 1024, y: -size / 1024)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // Background: the macOS icon shape (824 pt on the 1024 canvas, 185 pt corners), soft two-tone.
    let inset: CGFloat = 100
    let shape = rounded(inset, inset, 824, 824, 185)
    shape.addClip()
    NSGradient(colors: [rgb(0x8FA6FF), rgb(0x5B6BE6), rgb(0x4452C9)], atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
        .draw(in: shape, angle: -65)
    // A faint lighter band across the top for the two-tone feel.
    NSGradient(starting: rgb(0xFFFFFF, 0.18), ending: rgb(0xFFFFFF, 0))!.draw(in: shape, angle: -90)

    // Board panel with a soft shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x1B2466, 0.35).cgColor)
    rgb(0xF4F6FF).setFill()
    rounded(192, 232, 584, 520, 44).fill()
    ctx.restoreGState()

    // Three columns of cards.
    let columnTop: CGFloat = 276
    let columnHeight: CGFloat = 432
    let columnWidth: CGFloat = 160
    let gap: CGFloat = 24
    let firstX: CGFloat = 192 + 24
    let cardTints: [NSColor] = [rgb(0x9AA7F2), rgb(0x7F8DEA), rgb(0xB3BCF5)]
    let layouts: [[CGFloat]] = [[88, 60, 88], [60, 88, 60], [88, 88, 60]]   // card heights per column
    for column in 0..<3 {
        let x = firstX + CGFloat(column) * (columnWidth + gap)
        rgb(0xDDE3F8).setFill()
        rounded(x, columnTop, columnWidth, columnHeight, 24).fill()
        var y = columnTop + 20
        for (index, height) in layouts[column].enumerated() {
            cardTints[(column + index) % cardTints.count].setFill()
            rounded(x + 18, y, columnWidth - 36, height, 16).fill()
            // A lighter "title line" on each card.
            rgb(0xFFFFFF, 0.55).setFill()
            rounded(x + 34, y + 18, (columnWidth - 68) * (index == 1 ? 0.55 : 0.8), 14, 7).fill()
            y += height + 16
        }
    }

    // Hourglass in the bottom-right corner, overlapping the panel.
    let cx: CGFloat = 760, top: CGFloat = 560, bottom: CGFloat = 900
    let mid = (top + bottom) / 2
    let halfWidth: CGFloat = 92, neck: CGFloat = 14, capHeight: CGFloat = 40
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x1B2466, 0.35).cgColor)
    let glass = NSBezierPath()
    glass.move(to: NSPoint(x: cx - halfWidth + 8, y: top + capHeight))
    glass.line(to: NSPoint(x: cx + halfWidth - 8, y: top + capHeight))
    glass.curve(to: NSPoint(x: cx + neck, y: mid), controlPoint1: NSPoint(x: cx + halfWidth - 8, y: mid - 50), controlPoint2: NSPoint(x: cx + neck, y: mid - 40))
    glass.curve(to: NSPoint(x: cx + halfWidth - 8, y: bottom - capHeight), controlPoint1: NSPoint(x: cx + neck, y: mid + 40), controlPoint2: NSPoint(x: cx + halfWidth - 8, y: mid + 50))
    glass.line(to: NSPoint(x: cx - halfWidth + 8, y: bottom - capHeight))
    glass.curve(to: NSPoint(x: cx - neck, y: mid), controlPoint1: NSPoint(x: cx - halfWidth + 8, y: mid + 50), controlPoint2: NSPoint(x: cx - neck, y: mid + 40))
    glass.curve(to: NSPoint(x: cx - halfWidth + 8, y: top + capHeight), controlPoint1: NSPoint(x: cx - neck, y: mid - 40), controlPoint2: NSPoint(x: cx - halfWidth + 8, y: mid - 50))
    glass.close()
    rgb(0xFFE08A).setFill()
    glass.fill()
    ctx.restoreGState()

    // Sand: a pile at the bottom and a little left at the top.
    ctx.saveGState()
    glass.addClip()
    rgb(0xF2A93B).setFill()
    let pile = NSBezierPath()
    pile.move(to: NSPoint(x: cx - halfWidth, y: bottom - capHeight))
    pile.line(to: NSPoint(x: cx + halfWidth, y: bottom - capHeight))
    pile.line(to: NSPoint(x: cx + halfWidth, y: bottom - capHeight - 30))
    pile.curve(to: NSPoint(x: cx, y: bottom - capHeight - 96), controlPoint1: NSPoint(x: cx + 40, y: bottom - capHeight - 40), controlPoint2: NSPoint(x: cx + 12, y: bottom - capHeight - 96))
    pile.curve(to: NSPoint(x: cx - halfWidth, y: bottom - capHeight - 30), controlPoint1: NSPoint(x: cx - 12, y: bottom - capHeight - 96), controlPoint2: NSPoint(x: cx - 40, y: bottom - capHeight - 40))
    pile.close()
    pile.fill()
    let topSand = NSBezierPath()
    topSand.move(to: NSPoint(x: cx - 40, y: mid - 56))
    topSand.line(to: NSPoint(x: cx + 40, y: mid - 56))
    topSand.line(to: NSPoint(x: cx + 6, y: mid - 6))
    topSand.line(to: NSPoint(x: cx - 6, y: mid - 6))
    topSand.close()
    topSand.fill()
    rounded(cx - 3, mid - 10, 6, 60, 3).fill()   // the falling stream
    ctx.restoreGState()

    // Caps.
    rgb(0xF2A93B).setFill()
    rounded(cx - halfWidth, top, halfWidth * 2, capHeight, 14).fill()
    rounded(cx - halfWidth, bottom - capHeight, halfWidth * 2, capHeight, 14).fill()
    rgb(0xFFFFFF, 0.35).setFill()
    rounded(cx - halfWidth + 14, top + 8, halfWidth * 2 - 28, 10, 5).fill()

    ctx.restoreGState()
}

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    gc.cgContext.setAllowsAntialiasing(true)
    gc.cgContext.setShouldAntialias(true)
    drawIcon(in: gc.cgContext, size: CGFloat(size))
    gc.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let slots: [(String, Int)] = [("16x16", 1), ("16x16", 2), ("32x32", 1), ("32x32", 2), ("128x128", 1), ("128x128", 2),
                              ("256x256", 1), ("256x256", 2), ("512x512", 1), ("512x512", 2)]
var images: [[String: String]] = []
for (name, scale) in slots {
    let base = Int(name.split(separator: "x")[0])!
    let file = "icon_\(name)@\(scale)x.png"
    try render(base * scale).write(to: outDir.appendingPathComponent(file))
    images.append(["filename": file, "idiom": "mac", "scale": "\(scale)x", "size": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
if args.count >= 3 { try render(512).write(to: URL(fileURLWithPath: args[2])) }
print("wrote \(images.count) icons to \(outDir.path)")

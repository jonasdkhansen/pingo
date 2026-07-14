import AppKit

let canvasWidth = 1440
let canvasHeight = 840
let outputPath = CommandLine.arguments.dropFirst().first ?? "assets/pingo-readme-preview.png"

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(canvasHeight) - top - height, width: width, height: height)
}

func fill(_ frame: NSRect, color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
}

func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat,
          font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    value.draw(in: rect(x, top, width, height), withAttributes: attributes)
}

func symbol(_ name: String, x: CGFloat, top: CGFloat, size: CGFloat,
            pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return }
    let tintedImage = NSImage(size: image.size)
    tintedImage.lockFocus()
    image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    if let context = NSGraphicsContext.current?.cgContext {
        context.saveGState()
        context.setBlendMode(.sourceAtop)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: image.size))
        context.restoreGState()
    }
    tintedImage.unlockFocus()
    let frame = rect(x, top, size, size)
    tintedImage.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
}

func drawSeparator(x: CGFloat, top: CGFloat, width: CGFloat, color: NSColor) {
    fill(rect(x + 14, top, width - 28, 1), color: color)
}

func drawMenu(x: CGFloat, top: CGFloat, dark: Bool) {
    let width: CGFloat = 420
    let height: CGFloat = 642
    let foreground = dark ? color(0xf4f4f5) : color(0x202124)
    let secondary = dark ? color(0xa9abb0) : color(0x686b70)
    let divider = dark ? color(0xffffff, alpha: 0.11) : color(0x000000, alpha: 0.10)
    let panel = dark ? color(0x292a2e, alpha: 0.98) : color(0xf7f7f8, alpha: 0.98)
    let tile = dark ? color(0xffffff, alpha: 0.07) : color(0x000000, alpha: 0.055)
    let green = dark ? color(0x4bd66f) : color(0x22a447)
    let red = dark ? color(0xff625f) : color(0xd92d2a)
    let accent = dark ? color(0x72a8ff) : color(0x1672d4)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, alpha: dark ? 0.46 : 0.24)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    fill(rect(x, top, width, height), color: panel, radius: 14)
    NSGraphicsContext.restoreGraphicsState()

    let contentX = x + 18
    let contentWidth = width - 36

    fill(rect(contentX, top + 22, 46, 46), color: green.withAlphaComponent(0.15), radius: 23)
    symbol("wifi", x: contentX + 11, top: top + 33, size: 24,
           pointSize: 18, weight: .semibold, color: green)
    text("Connected", x: x + 80, top: top + 23, width: 280, height: 25,
         font: .systemFont(ofSize: 19, weight: .semibold), color: foreground)
    text("Checked at 14:32:08 — 2s ago", x: x + 80, top: top + 50, width: 285, height: 19,
         font: .monospacedDigitSystemFont(ofSize: 13, weight: .regular), color: secondary)
    symbol("info.circle", x: x + width - 42, top: top + 33, size: 18,
           pointSize: 14, weight: .medium, color: secondary)

    drawSeparator(x: x, top: top + 88, width: width, color: divider)

    let tileTop = top + 108
    let tileWidth: CGFloat = 112
    let tileGap: CGFloat = 10
    let tileValues = [("99%", "UPTIME"), ("284", "PINGS"), ("1", "FAILED")]
    for (index, item) in tileValues.enumerated() {
        let tileX = contentX + CGFloat(index) * (tileWidth + tileGap)
        fill(rect(tileX, tileTop, tileWidth, 62), color: tile, radius: 8)
        text(item.0, x: tileX, top: tileTop + 10, width: tileWidth, height: 23,
             font: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
             color: foreground, alignment: .center)
        text(item.1, x: tileX, top: tileTop + 39, width: tileWidth, height: 14,
             font: .systemFont(ofSize: 10, weight: .semibold), color: secondary, alignment: .center)
    }
    symbol("info.circle", x: x + width - 38, top: tileTop + 22, size: 16,
           pointSize: 13, weight: .medium, color: secondary)

    text("HISTORY", x: contentX, top: top + 192, width: 70, height: 15,
         font: .systemFont(ofSize: 10, weight: .semibold), color: secondary)
    var barX = x + 112
    let history = [true, true, true, true, true, false, true, true, true, true, true, true,
                   true, true, true, true, true, true, true, true, true, true, true, true]
    for result in history {
        let barHeight: CGFloat = result ? 12 : 20
        fill(rect(barX, top + 188 + (20 - barHeight) / 2, 6, barHeight),
             color: result ? green : red, radius: 3)
        barX += 10
    }
    symbol("info.circle", x: x + width - 38, top: top + 190, size: 16,
           pointSize: 13, weight: .medium, color: secondary)

    drawSeparator(x: x, top: top + 226, width: width, color: divider)

    func drawRow(_ rowTop: CGFloat, icon: String, label: String, info: Bool = true) {
        symbol(icon, x: contentX + 2, top: rowTop + 10, size: 19,
               pointSize: 15, weight: .medium, color: secondary)
        text(label, x: x + 50, top: rowTop + 9, width: 270, height: 22,
             font: .menuFont(ofSize: 16), color: foreground)
        if info {
            symbol("info.circle", x: x + width - 40, top: rowTop + 11, size: 17,
                   pointSize: 13, weight: .medium, color: secondary)
        }
    }

    drawRow(top + 238, icon: "pause.circle", label: "Pause Monitoring")
    drawRow(top + 280, icon: "arrow.clockwise", label: "Check Now")
    drawRow(top + 322, icon: "wand.and.stars", label: "Auto-Fix Wi-Fi", info: false)
    fill(rect(x + width - 77, top + 333, 42, 23), color: green, radius: 12)
    fill(rect(x + width - 56, top + 336, 17, 17), color: .white, radius: 9)
    symbol("info.circle", x: x + width - 107, top: top + 335, size: 17,
           pointSize: 13, weight: .medium, color: secondary)
    drawRow(top + 364, icon: "wifi.router", label: "Choose Backup Network", info: false)
    symbol("chevron.right", x: x + width - 38, top: top + 376, size: 13,
           pointSize: 11, weight: .semibold, color: secondary)

    drawSeparator(x: x, top: top + 416, width: width, color: divider)

    text("Check interval", x: contentX, top: top + 436, width: 170, height: 20,
         font: .systemFont(ofSize: 15, weight: .medium), color: foreground)
    text("every 15s", x: x + 272, top: top + 436, width: 92, height: 20,
         font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
         color: accent, alignment: .right)
    symbol("info.circle", x: x + width - 40, top: top + 438, size: 17,
           pointSize: 13, weight: .medium, color: secondary)
    fill(rect(contentX, top + 482, contentWidth, 4), color: divider, radius: 2)
    fill(rect(contentX, top + 482, contentWidth * 0.24, 4), color: accent, radius: 2)
    fill(rect(contentX + contentWidth * 0.24 - 8, top + 476, 16, 16),
         color: dark ? color(0xe4e5e7) : .white, radius: 8)

    drawSeparator(x: x, top: top + 524, width: width, color: divider)
    drawRow(top + 540, icon: "arrow.down.circle", label: "Check for Updates…")
    drawRow(top + 582, icon: "power", label: "Quit Pingo")

    text(dark ? "DARK" : "LIGHT", x: x, top: top + height + 25, width: width, height: 18,
         font: .systemFont(ofSize: 12, weight: .semibold),
         color: dark ? color(0x8d9097) : color(0x777b82), alignment: .center)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasWidth,
    pixelsHigh: canvasHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create image buffer")
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

fill(rect(0, 0, CGFloat(canvasWidth) / 2, CGFloat(canvasHeight)), color: color(0xe9edf2))
fill(rect(CGFloat(canvasWidth) / 2, 0, CGFloat(canvasWidth) / 2, CGFloat(canvasHeight)), color: color(0x181a1f))

drawMenu(x: 190, top: 40, dark: false)
drawMenu(x: 830, top: 40, dark: true)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("Rendered \(outputPath)")
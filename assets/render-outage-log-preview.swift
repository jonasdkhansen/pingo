import AppKit

let canvasWidth = 1440
let canvasHeight = 840
let arguments = CommandLine.arguments.dropFirst()
let lightMode = arguments.contains("--light")
let outputPath = arguments.first(where: { $0 != "--light" }) ?? "assets/pingo-outage-log-preview.png"

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
    value.draw(in: rect(x, top, width, height), withAttributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ])
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
    tintedImage.draw(in: rect(x, top, size, size), from: .zero, operation: .sourceOver, fraction: 1)
}

func drawPanel(_ frame: NSRect, color: NSColor, shadow: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let panelShadow = NSShadow()
    panelShadow.shadowColor = shadow
    panelShadow.shadowBlurRadius = 24
    panelShadow.shadowOffset = NSSize(width: 0, height: -8)
    panelShadow.set()
    fill(frame, color: color, radius: 12)
    NSGraphicsContext.restoreGraphicsState()
}

func drawPreview(x: CGFloat, dark: Bool) {
    let foreground = dark ? color(0xf4f4f5) : color(0x202124)
    let secondary = dark ? color(0xa9abb0) : color(0x686b70)
    let panel = dark ? color(0x292a2e, alpha: 0.98) : color(0xf7f7f8, alpha: 0.98)
    let divider = dark ? color(0xffffff, alpha: 0.11) : color(0x000000, alpha: 0.10)
    let selected = dark ? color(0x3d6fa8) : color(0x1672d4)
    let selectedText = color(0xffffff)
    let green = dark ? color(0x4bd66f) : color(0x22a447)
    let menuWidth: CGFloat = 300
    let menuTop: CGFloat = 96
    let menuHeight: CGFloat = 430
    let submenuX = x + 272
    let submenuTop: CGFloat = 174
    let submenuWidth: CGFloat = 270
    let submenuHeight: CGFloat = 314

    drawPanel(rect(x, menuTop, menuWidth, menuHeight), color: panel,
              shadow: color(0x000000, alpha: dark ? 0.44 : 0.22))
    fill(rect(x + 15, menuTop + 17, 36, 36), color: green.withAlphaComponent(0.15), radius: 18)
    symbol("wifi", x: x + 24, top: menuTop + 26, size: 18,
           pointSize: 15, weight: .semibold, color: green)
    text("Connected", x: x + 62, top: menuTop + 19, width: 170, height: 20,
         font: .systemFont(ofSize: 16, weight: .semibold), color: foreground)
    text("Checked at 14:32:08", x: x + 62, top: menuTop + 39, width: 190, height: 16,
         font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: secondary)
    fill(rect(x + 14, menuTop + 70, menuWidth - 28, 1), color: divider)

    let rows: [(String, String)] = [
        ("pause.circle", "Pause Monitoring"),
        ("arrow.clockwise", "Check Now"),
        ("clock.arrow.circlepath", "Outage Log"),
        ("wand.and.stars", "Auto-Fix Wi-Fi"),
        ("wifi.router", "Choose Backup Network")
    ]
    for (index, row) in rows.enumerated() {
        let rowTop = menuTop + 88 + CGFloat(index) * 48
        let isSelected = index == 2
        if isSelected {
            fill(rect(x + 7, rowTop - 3, menuWidth - 14, 38), color: selected, radius: 5)
        }
        let rowColor = isSelected ? selectedText : foreground
        symbol(row.0, x: x + 24, top: rowTop + 6, size: 19,
               pointSize: 14, weight: .medium, color: rowColor)
        text(row.1, x: x + 56, top: rowTop + 5, width: 195, height: 22,
             font: .menuFont(ofSize: 14), color: rowColor)
        if index == 2 || index == 4 {
            symbol("chevron.right", x: x + 264, top: rowTop + 9, size: 13,
                   pointSize: 10, weight: .semibold, color: rowColor)
        }
    }

    fill(rect(x + 14, menuTop + 338, menuWidth - 28, 1), color: divider)
    symbol("power", x: x + 24, top: menuTop + 361, size: 18,
           pointSize: 14, weight: .medium, color: foreground)
    text("Quit Pingo", x: x + 56, top: menuTop + 359, width: 180, height: 22,
         font: .menuFont(ofSize: 14), color: foreground)

    drawPanel(rect(submenuX, submenuTop, submenuWidth, submenuHeight), color: panel,
              shadow: color(0x000000, alpha: dark ? 0.48 : 0.24))
    text("OUTAGE LOG", x: submenuX + 16, top: submenuTop + 15, width: 150, height: 15,
         font: .systemFont(ofSize: 10, weight: .semibold), color: secondary)
    text("4 outages · newest first", x: submenuX + 16, top: submenuTop + 37,
         width: 220, height: 18, font: .menuFont(ofSize: 13), color: foreground)
    fill(rect(submenuX + 14, submenuTop + 65, submenuWidth - 28, 1), color: divider)

    let outages = ["Jul 15, 09:41:18 · 1m 42s", "Jul 14, 17:23:04 · 18s",
                   "Jul 12, 08:15:52 · 4m 7s", "Jul 10, 21:08:33 · 2m 31s"]
    for (index, outage) in outages.enumerated() {
        let rowTop = submenuTop + 78 + CGFloat(index) * 34
        text(outage, x: submenuX + 16, top: rowTop, width: submenuWidth - 32, height: 18,
             font: .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular), color: foreground)
    }

    fill(rect(submenuX + 14, submenuTop + 216, submenuWidth - 28, 1), color: divider)
    symbol("square.and.arrow.up", x: submenuX + 17, top: submenuTop + 234, size: 17,
           pointSize: 13, weight: .medium, color: foreground)
    text("Export Full Log…", x: submenuX + 45, top: submenuTop + 231,
         width: 185, height: 21, font: .menuFont(ofSize: 13), color: foreground)
    symbol("trash", x: submenuX + 17, top: submenuTop + 271, size: 17,
           pointSize: 13, weight: .medium, color: secondary)
    text("Clear Log", x: submenuX + 45, top: submenuTop + 268,
         width: 185, height: 21, font: .menuFont(ofSize: 13), color: secondary)

    text(dark ? "DARK" : "LIGHT", x: x, top: 560, width: submenuX + submenuWidth - x,
         height: 18, font: .systemFont(ofSize: 12, weight: .semibold),
         color: dark ? color(0x8d9097) : color(0x777b82), alignment: .center)
}

    func drawReferencePreview(lightMode: Bool) {
        let menuX: CGFloat = 180
        let menuTop: CGFloat = 42
        let menuWidth: CGFloat = 565
        let foreground = lightMode ? color(0x202124) : color(0xe7e7e8)
        let secondary = lightMode ? color(0x686b70) : color(0x939599)
        let divider = lightMode ? color(0x000000, alpha: 0.10) : color(0xffffff, alpha: 0.15)
        let green = lightMode ? color(0x22a447) : color(0x2bd75e)
        let panelColor = lightMode ? color(0xf7f7f8, alpha: 0.985) : color(0x202123, alpha: 0.985)
        let tileColor = lightMode ? color(0x000000, alpha: 0.055) : color(0xffffff, alpha: 0.075)
        let selectedColor = lightMode ? color(0x1672d4) : color(0x2669cb)
        let shadowColor = color(0x000000, alpha: lightMode ? 0.22 : 0.48)

        func line(_ top: CGFloat) {
           fill(rect(menuX + 23, top, menuWidth - 46, 1), color: divider)
        }
        func info(_ x: CGFloat, _ top: CGFloat, _ tint: NSColor = secondary) {
           symbol("info.circle", x: x, top: top, size: 25, pointSize: 19, weight: .regular, color: tint)
        }
        func row(_ top: CGFloat, _ icon: String, _ title: String, selected: Bool = false,
               chevron: Bool = false, includeInfo: Bool = true) {
           let textColor = selected ? NSColor.white : foreground
           if selected {
            fill(rect(menuX + 7, top - 4, menuWidth - 14, 42), color: selectedColor, radius: 9)
           }
           symbol(icon, x: menuX + 26, top: top + 5, size: 25,
                pointSize: 19, weight: .medium, color: textColor)
           text(title, x: menuX + 70, top: top + 3, width: menuWidth - 145, height: 30,
               font: .menuFont(ofSize: 21), color: textColor)
           if chevron {
              symbol("chevron.right", x: menuX + menuWidth - 39, top: top + 9, size: 19,
                    pointSize: 15, weight: .bold, color: textColor)
           } else if includeInfo {
              info(menuX + menuWidth - 49, top + 5, selected ? .white : secondary)
           }
        }

    let outageEntries = [
        "Jul 15, 14:23:16 · 1s", "Jul 15, 13:03:11 · 1h 10m", "Jul 15, 12:31:46 · 1s",
        "Jul 15, 12:11:26 · 11s", "Jul 15, 12:01:21 · 18s", "Jul 15, 11:44:36 · 17s",
        "Jul 15, 11:19:26 · 4m 36s", "Jul 15, 11:13:46 · 1s", "Jul 15, 10:59:21 · 28s"
    ]
    let totalPings = 4_321
    let failedPings = 90
    let uptime = (totalPings - failedPings) * 100 / totalPings
    let countFormatter = NumberFormatter()
    countFormatter.numberStyle = .decimal
    let formattedTotalPings = countFormatter.string(from: NSNumber(value: totalPings)) ?? "\(totalPings)"
    let recentChecks = [true, true, true, true, false, false, true, true, true, true, true, true,
                        true, true, true, true, true, true, true, true, true, true, true, true, true]

        drawPanel(rect(menuX, menuTop, menuWidth, 790), color: panelColor, shadow: shadowColor)
        fill(rect(menuX + 26, menuTop + 28, 76, 76), color: green.withAlphaComponent(0.15), radius: 38)
        symbol("wifi", x: menuX + 45, top: menuTop + 48, size: 37,
             pointSize: 30, weight: .bold, color: green)
        text("Connected", x: menuX + 123, top: menuTop + 31, width: 330, height: 38,
            font: .systemFont(ofSize: 30, weight: .semibold), color: foreground)
        text("Checked at 15:08:10 — 4s ago", x: menuX + 123, top: menuTop + 72, width: 350, height: 29,
            font: .monospacedDigitSystemFont(ofSize: 20, weight: .regular), color: secondary)
        info(menuX + menuWidth - 58, menuTop + 50)
        line(menuTop + 128)

        let tileTop = menuTop + 146
        let tileWidth: CGFloat = 154
        let tiles = [("\(uptime)%", "UPTIME"), (formattedTotalPings, "PINGS"), ("\(failedPings)", "FAILED")]
        for (index, tile) in tiles.enumerated() {
           let tileX = menuX + 22 + CGFloat(index) * 170
        fill(rect(tileX, tileTop, tileWidth, 75), color: tileColor, radius: 14)
           text(tile.0, x: tileX, top: tileTop + 14, width: tileWidth, height: 30,
               font: .monospacedDigitSystemFont(ofSize: 26, weight: .semibold), color: foreground, alignment: .center)
           text(tile.1, x: tileX, top: tileTop + 50, width: tileWidth, height: 18,
               font: .systemFont(ofSize: 15, weight: .semibold), color: secondary, alignment: .center)
        }
        info(menuX + menuWidth - 58, tileTop + 25)

        text("HISTORY", x: menuX + 30, top: menuTop + 236, width: 100, height: 22,
            font: .systemFont(ofSize: 16, weight: .semibold), color: secondary)
        var barX = menuX + 143
        let red = lightMode ? color(0xd92d2a) : color(0xff625f)
        for result in recentChecks {
            fill(rect(barX, menuTop + 236, 10, 19), color: result ? green : red, radius: 5)
           barX += 14
        }
        info(menuX + menuWidth - 58, menuTop + 232)

        row(menuTop + 281, "clock.arrow.circlepath", "Outage Log", selected: true, chevron: true, includeInfo: false)
        line(menuTop + 329)
        row(menuTop + 351, "pause.circle", "Pause Monitoring")
        row(menuTop + 399, "arrow.clockwise", "Check Now")
        row(menuTop + 447, "wand.and.stars", "Auto-Fix Wi-Fi", includeInfo: false)
        info(menuX + menuWidth - 142, menuTop + 452)
        fill(rect(menuX + menuWidth - 86, menuTop + 452, 63, 31), color: green, radius: 16)
        fill(rect(menuX + menuWidth - 53, menuTop + 457, 21, 21), color: .white, radius: 11)
        row(menuTop + 495, "wifi.router", "Choose Backup Network", chevron: true, includeInfo: false)
        line(menuTop + 544)

        text("Check interval", x: menuX + 30, top: menuTop + 561, width: 220, height: 28,
            font: .systemFont(ofSize: 21, weight: .semibold), color: foreground)
        text("every 5s", x: menuX + menuWidth - 170, top: menuTop + 561, width: 110, height: 28,
            font: .monospacedDigitSystemFont(ofSize: 19, weight: .semibold), color: color(0x0a84ff), alignment: .right)
        info(menuX + menuWidth - 58, menuTop + 562)
            fill(rect(menuX + 23, menuTop + 615, menuWidth - 46, 11),
                color: lightMode ? color(0x000000, alpha: 0.16) : color(0xffffff, alpha: 0.16), radius: 6)
            fill(rect(menuX + 44, menuTop + 604, 38, 38), color: lightMode ? .white : color(0xe7e8ea), radius: 19)
        line(menuTop + 666)
        row(menuTop + 686, "arrow.down.circle", "Check for Updates…")
        row(menuTop + 734, "power", "Quit Pingo")

        let submenuX = menuX + menuWidth - 5
        let submenuTop: CGFloat = 232
        let submenuWidth: CGFloat = 365
        let submenuHeight: CGFloat = 566
        drawPanel(rect(submenuX, submenuTop, submenuWidth, submenuHeight),
                  color: lightMode ? color(0xf7f7f8, alpha: 0.99) : color(0x242528, alpha: 0.99),
                  shadow: color(0x000000, alpha: lightMode ? 0.24 : 0.52))
        text("\(outageEntries.count) outages · newest first", x: submenuX + 21, top: submenuTop + 20, width: submenuWidth - 42, height: 26,
            font: .menuFont(ofSize: 18), color: foreground)
        fill(rect(submenuX + 20, submenuTop + 55, submenuWidth - 40, 1), color: divider)

        for (index, outage) in outageEntries.enumerated() {
           text(outage, x: submenuX + 21, top: submenuTop + 75 + CGFloat(index) * 41,
               width: submenuWidth - 42, height: 23,
               font: .monospacedDigitSystemFont(ofSize: 15, weight: .regular), color: foreground)
        }
        fill(rect(submenuX + 20, submenuTop + 453, submenuWidth - 40, 1), color: divider)
        text("Export Full Log…", x: submenuX + 21, top: submenuTop + 473, width: submenuWidth - 42, height: 27,
            font: .menuFont(ofSize: 20), color: foreground)
        text("Clear Log", x: submenuX + 21, top: submenuTop + 514, width: submenuWidth - 42, height: 27,
            font: .menuFont(ofSize: 20), color: secondary)
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

fill(rect(0, 0, CGFloat(canvasWidth), CGFloat(canvasHeight)), color: lightMode ? color(0xe9edf2) : color(0x18191b))
drawReferencePreview(lightMode: lightMode)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("Rendered \(outputPath)")
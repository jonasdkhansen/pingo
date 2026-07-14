import AppKit

guard CommandLine.arguments.count == 3 else {
    fputs("usage: render-app-icon.swift <source.png> <output.png>\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to read \(sourceURL.path)\n", stderr)
    exit(66)
}

let canvasSize = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Unable to create output bitmap\n", stderr)
    exit(70)
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create graphics context\n", stderr)
    exit(70)
}
NSGraphicsContext.current = graphicsContext
graphicsContext.cgContext.clear(NSRect(origin: .zero, size: canvasSize))

let iconRect = NSRect(x: 54, y: 54, width: 916, height: 916)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 205, yRadius: 205)
iconPath.addClip()

let sourceCrop = NSRect(
    x: source.size.width * 0.055,
    y: source.size.height * 0.055,
    width: source.size.width * 0.89,
    height: source.size.height * 0.89
)
source.draw(
    in: iconRect,
    from: sourceCrop,
    operation: .copy,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)

if let topGlass = NSGradient(colorsAndLocations:
    (NSColor.white.withAlphaComponent(0.20), 0),
    (NSColor.white.withAlphaComponent(0.05), 0.24),
    (NSColor.clear, 0.55)
) {
    topGlass.draw(in: iconRect, angle: -90)
}

if let lowerGlass = NSGradient(colorsAndLocations:
    (NSColor.clear, 0.48),
    (NSColor(calibratedRed: 0.02, green: 0.24, blue: 0.36, alpha: 0.12), 1)
) {
    lowerGlass.draw(in: iconRect, angle: -90)
}

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

NSColor.white.withAlphaComponent(0.30).setStroke()
iconPath.lineWidth = 4
iconPath.stroke()

let innerPath = NSBezierPath(
    roundedRect: iconRect.insetBy(dx: 10, dy: 10),
    xRadius: 195,
    yRadius: 195
)
NSColor(calibratedRed: 0.34, green: 0.78, blue: 1, alpha: 0.22).setStroke()
innerPath.lineWidth = 2
innerPath.stroke()

let highlight = NSBezierPath()
highlight.move(to: NSPoint(x: 230, y: 951))
highlight.curve(
    to: NSPoint(x: 794, y: 951),
    controlPoint1: NSPoint(x: 360, y: 966),
    controlPoint2: NSPoint(x: 664, y: 966)
)
NSColor.white.withAlphaComponent(0.24).setStroke()
highlight.lineWidth = 3
highlight.lineCapStyle = .round
highlight.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode PNG\n", stderr)
    exit(70)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Unable to write \(outputURL.path): \(error)\n", stderr)
    exit(73)
}
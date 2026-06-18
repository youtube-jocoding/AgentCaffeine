import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift dmg_background.swift /path/to/background.png\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 748, height: 414)

func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: size.height - y - height, width: width, height: height)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to allocate DMG background bitmap\n", stderr)
    exit(1)
}
bitmap.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1),
    .paragraphStyle: titleStyle
]
"Drag to Applications".draw(
    in: rectFromTop(x: 0, y: 48, width: size.width, height: 34),
    withAttributes: titleAttributes
)

let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
    .paragraphStyle: titleStyle
]
"Install AgentCaffeine by dragging the app icon into the Applications folder.".draw(
    in: rectFromTop(x: 90, y: 82, width: size.width - 180, height: 22),
    withAttributes: subtitleAttributes
)

let arrowColor = NSColor(calibratedRed: 0.32, green: 0.52, blue: 0.66, alpha: 0.75)
arrowColor.setStroke()
arrowColor.setFill()

let arrowY = size.height - 168
let arrowPath = NSBezierPath()
arrowPath.lineWidth = 8
arrowPath.lineCapStyle = .round
arrowPath.move(to: NSPoint(x: 292, y: arrowY))
arrowPath.line(to: NSPoint(x: 456, y: arrowY))
arrowPath.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 456, y: arrowY + 24))
arrowHead.line(to: NSPoint(x: 492, y: arrowY))
arrowHead.line(to: NSPoint(x: 456, y: arrowY - 24))
arrowHead.line(to: NSPoint(x: 466, y: arrowY))
arrowHead.close()
arrowHead.fill()

let hintStyle = NSMutableParagraphStyle()
hintStyle.alignment = .center
let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.48, alpha: 1),
    .paragraphStyle: hintStyle
]
"1. Drag".draw(in: rectFromTop(x: 120, y: 276, width: 120, height: 20), withAttributes: hintAttributes)
"2. Drop".draw(in: rectFromTop(x: 505, y: 276, width: 120, height: 20), withAttributes: hintAttributes)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render DMG background\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)

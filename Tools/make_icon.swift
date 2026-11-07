import AppKit
import Foundation

let size = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    exit(1)
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = NSRect(x: 0, y: 0, width: size, height: size)

// Rounded midnight-blue background.
let backgroundPath = NSBezierPath(
    roundedRect: canvas.insetBy(dx: 36, dy: 36),
    xRadius: 220,
    yRadius: 220
)
let background = NSGradient(
    starting: NSColor(calibratedRed: 0.035, green: 0.10, blue: 0.22, alpha: 1),
    ending: NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.56, alpha: 1)
)!
background.draw(in: backgroundPath, angle: -90)

NSColor.white.withAlphaComponent(0.13).setStroke()
backgroundPath.lineWidth = 6
backgroundPath.stroke()

// Metal USB connector.
let connectorRect = NSRect(x: 420, y: 772, width: 184, height: 196)
let connector = NSBezierPath(roundedRect: connectorRect, xRadius: 22, yRadius: 22)
let connectorGradient = NSGradient(
    starting: NSColor(calibratedWhite: 0.98, alpha: 1),
    ending: NSColor(calibratedWhite: 0.62, alpha: 1)
)!
connectorGradient.draw(in: connector, angle: -90)
NSColor(calibratedWhite: 0.35, alpha: 0.55).setStroke()
connector.lineWidth = 6
connector.stroke()

// Connector contacts.
for row in 0..<2 {
    let y = connectorRect.maxY - 52 - CGFloat(row) * 42
    let contact = NSBezierPath(
        roundedRect: NSRect(x: connectorRect.minX + 32, y: y, width: connectorRect.width - 64, height: 16),
        xRadius: 8,
        yRadius: 8
    )
    NSColor(calibratedWhite: 0.40, alpha: 0.45).setFill()
    contact.fill()
}

// Drive body.
let bodyRect = NSRect(x: 348, y: 150, width: 328, height: 646)
let body = NSBezierPath(roundedRect: bodyRect, xRadius: 76, yRadius: 76)
let bodyGradient = NSGradient(
    starting: NSColor(calibratedRed: 0.14, green: 0.50, blue: 0.92, alpha: 1),
    ending: NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.55, alpha: 1)
)!
bodyGradient.draw(in: body, angle: -90)

NSColor.white.withAlphaComponent(0.35).setStroke()
body.lineWidth = 6
body.stroke()

// Light band with the ISO label.
let band = NSBezierPath(
    roundedRect: NSRect(x: 384, y: 470, width: 256, height: 128),
    xRadius: 28,
    yRadius: 28
)
NSColor.white.withAlphaComponent(0.92).setFill()
band.fill()

let isoText = NSAttributedString(
    string: "ISO",
    attributes: [
        .font: NSFont.systemFont(ofSize: 86, weight: .heavy),
        .foregroundColor: NSColor(calibratedRed: 0.05, green: 0.24, blue: 0.52, alpha: 1),
        .kern: 2
    ]
)
let textSize = isoText.size()
isoText.draw(
    at: NSPoint(x: 512 - textSize.width / 2, y: 534 - textSize.height / 2)
)

// Lanyard hole.
let hole = NSBezierPath(
    ovalIn: NSRect(x: 512 - 34, y: 214, width: 68, height: 68)
)
NSColor(calibratedRed: 0.035, green: 0.10, blue: 0.22, alpha: 1).setFill()
hole.fill()
NSColor.white.withAlphaComponent(0.30).setStroke()
hole.lineWidth = 6
hole.stroke()

// Orange badge with a lightning bolt.
let badgeCenter = NSPoint(x: 762, y: 286)
let badgeRadius: CGFloat = 120
let badge = NSBezierPath(
    ovalIn: NSRect(
        x: badgeCenter.x - badgeRadius,
        y: badgeCenter.y - badgeRadius,
        width: badgeRadius * 2,
        height: badgeRadius * 2
    )
)
let badgeGradient = NSGradient(
    starting: NSColor(calibratedRed: 1.0, green: 0.64, blue: 0.05, alpha: 1),
    ending: NSColor(calibratedRed: 1.0, green: 0.20, blue: 0.10, alpha: 1)
)!
badgeGradient.draw(in: badge, angle: -90)
NSColor.white.withAlphaComponent(0.9).setStroke()
badge.lineWidth = 7
badge.stroke()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: badgeCenter.x + 18, y: badgeCenter.y + 74))
bolt.line(to: NSPoint(x: badgeCenter.x - 52, y: badgeCenter.y - 8))
bolt.line(to: NSPoint(x: badgeCenter.x - 4, y: badgeCenter.y - 8))
bolt.line(to: NSPoint(x: badgeCenter.x - 20, y: badgeCenter.y - 74))
bolt.line(to: NSPoint(x: badgeCenter.x + 52, y: badgeCenter.y + 8))
bolt.line(to: NSPoint(x: badgeCenter.x + 4, y: badgeCenter.y + 8))
bolt.close()
NSColor.white.setFill()
bolt.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try png.write(to: URL(fileURLWithPath: output))
print(output)

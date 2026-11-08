// Generates Icon/icon-1024.png for Citlla E510 without any external tools.
// Run with: swift Icon/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

// Background squircle.
let bodyRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: bodyRect, xRadius: 186, yRadius: 186)
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)
])!
background.draw(in: squircle, angle: -90)

// Soft top highlight.
context.saveGState()
squircle.addClip()
let glow = NSGradient(
    starting: NSColor(calibratedWhite: 1, alpha: 0.18),
    ending: NSColor(calibratedWhite: 1, alpha: 0)
)!
glow.draw(
    fromCenter: NSPoint(x: 512, y: 850),
    radius: 0,
    toCenter: NSPoint(x: 512, y: 520),
    radius: 470,
    options: []
)
context.restoreGState()

// Inner rim.
NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
squircle.lineWidth = 4
squircle.stroke()

// Mouse body with shadow.
let body = NSBezierPath(
    roundedRect: NSRect(x: 352, y: 190, width: 320, height: 650),
    xRadius: 160,
    yRadius: 160
)
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.55)
shadow.shadowBlurRadius = 38
shadow.shadowOffset = NSSize(width: 0, height: -22)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()

let bodyGradient = NSGradient(colors: [
    NSColor(calibratedWhite: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.82, green: 0.84, blue: 0.88, alpha: 1),
    NSColor(calibratedRed: 0.67, green: 0.70, blue: 0.75, alpha: 1)
])!
bodyGradient.draw(in: body, angle: -90)

NSColor(calibratedWhite: 0.25, alpha: 0.16).setStroke()
body.lineWidth = 3
body.stroke()

// Right/left split near the top, like a mouse shell.
let split = NSBezierPath()
split.move(to: NSPoint(x: 512, y: 840))
split.line(to: NSPoint(x: 512, y: 610))
NSColor(calibratedWhite: 0.32, alpha: 0.30).setStroke()
split.lineWidth = 4
split.lineCapStyle = .round
split.stroke()

// Scroll wheel.
let wheel = NSBezierPath(
    roundedRect: NSRect(x: 480, y: 620, width: 64, height: 160),
    xRadius: 32,
    yRadius: 32
)
let wheelGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.31, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1)
])!
wheelGradient.draw(in: wheel, angle: -90)
NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
wheel.lineWidth = 3
wheel.stroke()

// Wheel highlight.
let wheelGlow = NSBezierPath(
    roundedRect: NSRect(x: 496, y: 704, width: 10, height: 56),
    xRadius: 5,
    yRadius: 5
)
NSColor(calibratedWhite: 1, alpha: 0.32).setFill()
wheelGlow.fill()

// Two orange side buttons, protruding slightly on the left.
let orange = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.28, alpha: 1),
    NSColor(calibratedRed: 0.94, green: 0.43, blue: 0.05, alpha: 1)
])!
for y in [430.0, 330.0] {
    let button = NSBezierPath(
        roundedRect: NSRect(x: 310, y: y, width: 78, height: 78),
        xRadius: 39,
        yRadius: 39
    )
    let buttonShadow = NSShadow()
    buttonShadow.shadowColor = NSColor(calibratedRed: 0.45, green: 0.16, blue: 0, alpha: 0.45)
    buttonShadow.shadowBlurRadius = 14
    buttonShadow.shadowOffset = NSSize(width: 0, height: -4)
    NSGraphicsContext.saveGraphicsState()
    buttonShadow.set()
    orange.draw(in: button, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
    button.lineWidth = 3
    button.stroke()
}

// A couple of subtle shell lines near the bottom.
for y in [300.0, 270.0] {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 430, y: y))
    line.line(to: NSPoint(x: 594, y: y))
    NSColor(calibratedWhite: 0.30, alpha: 0.12).setStroke()
    line.lineWidth = 5
    line.lineCapStyle = .round
    line.stroke()
}

NSGraphicsContext.restoreGraphicsState()

let output = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("icon-1024.png")
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: output)
print("wrote \(output.path)")

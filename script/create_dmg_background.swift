#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: create_dmg_background.swift <output.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let scale: CGFloat = 2
let size = NSSize(width: 760 * scale, height: 460 * scale)
let image = NSImage(size: size)

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
}

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.95, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

NSColor(calibratedWhite: 0.72, alpha: 0.34).setFill()
for x in stride(from: 12, through: 748, by: 16) {
    for y in stride(from: 12, through: 448, by: 16) {
        NSBezierPath(ovalIn: rect(CGFloat(x), CGFloat(y), 1.7, 1.7)).fill()
    }
}

let dropZone = NSBezierPath(roundedRect: rect(430, 126, 250, 168), xRadius: 10 * scale, yRadius: 10 * scale)
NSColor(calibratedWhite: 0.90, alpha: 0.88).setFill()
dropZone.fill()
NSColor(calibratedWhite: 0.62, alpha: 0.35).setStroke()
dropZone.lineWidth = 1 * scale
dropZone.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 314 * scale, y: 230 * scale))
arrow.line(to: NSPoint(x: 407 * scale, y: 230 * scale))
NSColor(calibratedWhite: 1.0, alpha: 0.92).setStroke()
arrow.lineWidth = 18 * scale
arrow.lineCapStyle = .round
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 408 * scale, y: 230 * scale))
arrowHead.line(to: NSPoint(x: 374 * scale, y: 260 * scale))
arrowHead.line(to: NSPoint(x: 374 * scale, y: 200 * scale))
arrowHead.close()
NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
arrowHead.fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Roobert-SemiBold", size: 19 * scale) ?? NSFont.systemFont(ofSize: 19 * scale, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 0.78)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Roobert-Regular", size: 13 * scale) ?? NSFont.systemFont(ofSize: 13 * scale),
    .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 0.70)
]

("Drag Cribble into Applications" as NSString).draw(
    at: NSPoint(x: 56 * scale, y: 394 * scale),
    withAttributes: titleAttributes
)
("Your Markdown library, installed the Mac way." as NSString).draw(
    at: NSPoint(x: 56 * scale, y: 370 * scale),
    withAttributes: subtitleAttributes
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Could not render DMG background.\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)

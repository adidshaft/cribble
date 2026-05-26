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

let scale: CGFloat = 1
let size = NSSize(width: 760 * scale, height: 460 * scale)
let image = NSImage(size: size)

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
}

image.lockFocus()

NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.952, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

NSColor(calibratedWhite: 0.60, alpha: 0.18).setFill()
for x in stride(from: 12, through: 748, by: 14) {
    for y in stride(from: 14, through: 446, by: 14) {
        NSBezierPath(ovalIn: rect(CGFloat(x), CGFloat(y), 1.4, 1.4)).fill()
    }
}

let dropZone = NSBezierPath(roundedRect: rect(430, 126, 250, 168), xRadius: 10 * scale, yRadius: 10 * scale)
NSColor(calibratedWhite: 0.88, alpha: 0.92).setFill()
dropZone.fill()
NSColor(calibratedWhite: 0.58, alpha: 0.32).setStroke()
dropZone.lineWidth = 1 * scale
dropZone.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 330 * scale, y: 230 * scale))
arrow.line(to: NSPoint(x: 414 * scale, y: 230 * scale))
NSColor(calibratedWhite: 1.0, alpha: 0.94).setStroke()
arrow.lineWidth = 18 * scale
arrow.lineCapStyle = .round
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 414 * scale, y: 230 * scale))
arrowHead.line(to: NSPoint(x: 380 * scale, y: 260 * scale))
arrowHead.line(to: NSPoint(x: 380 * scale, y: 200 * scale))
arrowHead.close()
NSColor(calibratedWhite: 1.0, alpha: 0.94).setFill()
arrowHead.fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Roobert-SemiBold", size: 18 * scale) ?? NSFont.systemFont(ofSize: 18 * scale, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 0.72)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Roobert-Regular", size: 12 * scale) ?? NSFont.systemFont(ofSize: 12 * scale),
    .foregroundColor: NSColor(calibratedWhite: 0.32, alpha: 0.58)
]

let title = "Drag and drop Cribble into Applications" as NSString
let subtitle = "Then open it from Applications." as NSString
let titleSize = title.size(withAttributes: titleAttributes)
let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
title.draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: 392 * scale),
    withAttributes: titleAttributes
)
subtitle.draw(
    at: NSPoint(x: (size.width - subtitleSize.width) / 2, y: 370 * scale),
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

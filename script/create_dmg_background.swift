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

func drawRadialGlow(center: NSPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    guard let gradient = NSGradient(colors: [
        color.withAlphaComponent(alpha),
        color.withAlphaComponent(0)
    ]) else { return }

    gradient.draw(
        fromCenter: NSPoint(x: center.x * scale, y: center.y * scale),
        radius: 0,
        toCenter: NSPoint(x: center.x * scale, y: center.y * scale),
        radius: radius * scale,
        options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
    )
}

image.lockFocus()

NSColor(calibratedRed: 0.105, green: 0.102, blue: 0.096, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

drawRadialGlow(
    center: NSPoint(x: 208, y: 250),
    radius: 210,
    color: NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.86, alpha: 1),
    alpha: 0.18
)
drawRadialGlow(
    center: NSPoint(x: 556, y: 242),
    radius: 190,
    color: NSColor(calibratedRed: 0.62, green: 0.64, blue: 0.68, alpha: 1),
    alpha: 0.10
)

NSColor(calibratedWhite: 1, alpha: 0.025).setFill()
for x in stride(from: 32, through: 728, by: 20) {
    for y in stride(from: 54, through: 408, by: 20) {
        NSBezierPath(ovalIn: rect(CGFloat(x), CGFloat(y), 1.3, 1.3)).fill()
    }
}

NSColor(calibratedWhite: 1, alpha: 0.055).setStroke()
let centerLine = NSBezierPath()
centerLine.move(to: NSPoint(x: 380 * scale, y: 116 * scale))
centerLine.line(to: NSPoint(x: 380 * scale, y: 336 * scale))
centerLine.lineWidth = 1 * scale
centerLine.stroke()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Roobert-SemiBold", size: 22 * scale) ?? NSFont.systemFont(ofSize: 22 * scale, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.94, alpha: 0.88)
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Roobert-Regular", size: 13 * scale) ?? NSFont.systemFont(ofSize: 13 * scale),
    .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 0.52)
]

let title = "Drag and drop Cribble into Applications" as NSString
let subtitle = "Then open it from Applications." as NSString
let titleSize = title.size(withAttributes: titleAttributes)
let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
title.draw(
    at: NSPoint(x: (size.width - titleSize.width) / 2, y: 372 * scale),
    withAttributes: titleAttributes
)
subtitle.draw(
    at: NSPoint(x: (size.width - subtitleSize.width) / 2, y: 348 * scale),
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

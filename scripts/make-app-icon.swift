#!/usr/bin/env swift

// Generates the Tapeek app icon from a single 1024 x 1024 vector master.
//
// The script uses only system frameworks (CoreGraphics, ImageIO, Foundation).
// It writes the master to docs/assets/tapeek-icon.png, then uses sips to make
// every Xcode macOS AppIcon size from that exact file.
//
// Usage: swift scripts/make-app-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasSize = 1024
let iconSetURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("TapeekApp/Assets.xcassets/AppIcon.appiconset")
let readmeIconURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("docs/assets/tapeek-icon.png")

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: canvasSize,
    height: canvasSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create the bitmap context")
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high
context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255
    let green = CGFloat((hex >> 8) & 0xFF) / 255
    let blue = CGFloat(hex & 0xFF) / 255
    return CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

// Coordinates below are entered in a top-left origin system and converted to
// CoreGraphics' bottom-left origin here. This keeps the composition readable.
func point(_ x: CGFloat, _ top: CGFloat) -> CGPoint {
    CGPoint(x: x, y: CGFloat(canvasSize) - top)
}

func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(canvasSize) - top - height, width: width, height: height)
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func squirclePath(in rect: CGRect, exponent: CGFloat = 4.8, steps: Int = 8192) -> CGPath {
    let path = CGMutablePath()
    for index in 0...steps {
        let angle = CGFloat(index) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = rect.midX + rect.width / 2 * copysign(pow(abs(cosine), 2 / exponent), cosine)
        let y = rect.midY + rect.height / 2 * copysign(pow(abs(sine), 2 / exponent), sine)
        if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func fill(_ path: CGPath, with color: CGColor) {
    context.saveGState()
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
    context.restoreGState()
}

func stroke(_ path: CGPath, color: CGColor, width: CGFloat) {
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.strokePath()
    context.restoreGState()
}

func fillLinearGradient(
    _ path: CGPath,
    colors: [CGColor],
    locations: [CGFloat],
    start: CGPoint,
    end: CGPoint
) {
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

func drawRoundedBar(
    x: CGFloat,
    top: CGFloat,
    width: CGFloat,
    height: CGFloat,
    color fillColor: CGColor
) {
    let bar = roundedPath(rect(x, top, width, height), radius: height / 2)
    fill(bar, with: fillColor)
}

// MARK: - Backplate

let plateRect = CGRect(x: 82, y: 82, width: 860, height: 860)
let plate = squirclePath(in: plateRect)

// A restrained drop shadow keeps the icon seated on light and dark wallpapers.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -20), blur: 34, color: color(0x000000, 0.32))
fill(plate, with: color(0x071A29))
context.restoreGState()

fillLinearGradient(
    plate,
    colors: [color(0x081A2B), color(0x0B3446), color(0x0A625C)],
    locations: [0, 0.47, 1],
    start: point(262, 112),
    end: point(790, 936)
)

context.saveGState()
context.addPath(plate)
context.clip()

// A narrow top highlight and a deeper bottom edge give the plate a soft
// enamel-like material quality without adding visual noise.
fillLinearGradient(
    plate,
    colors: [color(0xFFFFFF, 0.13), color(0xFFFFFF, 0.0), color(0x001018, 0.0), color(0x001018, 0.16)],
    locations: [0, 0.18, 0.72, 1],
    start: point(512, 82),
    end: point(512, 942)
)
context.restoreGState()

// Hairline rim light, strongest at the top.
context.saveGState()
context.addPath(plate)
context.clip()
context.setLineWidth(3)
context.setStrokeColor(color(0xFFFFFF, 0.14))
context.strokePath()
context.restoreGState()

// MARK: - Sheets and magnifier

// Keep the composition optically centred. The group is slightly wider on the
// right because of the magnifier, so nudge it left and down from its raw
// drawing coordinates.
context.saveGState()
context.translateBy(x: -28, y: -16)

// Back sheet (ZIP)
let backSheetPath = roundedPath(rect(240, 204, 408, 512), radius: 32)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 32, color: color(0x00161B, 0.28))
fill(backSheetPath, with: color(0xD5E7E1))
context.restoreGState()

fillLinearGradient(
    backSheetPath,
    colors: [color(0xE9F3ED), color(0xC9E2DC)],
    locations: [0, 1],
    start: point(300, 210),
    end: point(640, 720)
)
stroke(backSheetPath, color: color(0xFFFFFF, 0.42), width: 1.5)

// Zipper track: a vertical dashed spine with paired teeth. It stays subtle at
// small sizes and becomes a clear ZIP cue at 128 px and above.
let zipperColor = color(0x3D7773, 0.58)
let zipSpine = CGMutablePath()
zipSpine.move(to: point(286, 298))
zipSpine.addLine(to: point(286, 654))
context.saveGState()
context.addPath(zipSpine)
context.setStrokeColor(zipperColor)
context.setLineWidth(5)
context.setLineCap(.round)
context.setLineDash(phase: 0, lengths: [13, 13])
context.strokePath()
context.restoreGState()

for index in 0..<11 {
    let top = 310 + CGFloat(index) * 31
    drawRoundedBar(x: 270, top: top, width: 13, height: 6, color: zipperColor)
    drawRoundedBar(x: 289, top: top, width: 13, height: 6, color: zipperColor)
}

// MARK: - Front sheet (document)

let frontSheetPath = roundedPath(rect(334, 278, 392, 500), radius: 28)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: color(0x00161B, 0.24))
fill(frontSheetPath, with: color(0xF7F5ED))
context.restoreGState()

fillLinearGradient(
    frontSheetPath,
    colors: [color(0xFFFDF7), color(0xEFF3EC)],
    locations: [0, 1],
    start: point(370, 282),
    end: point(690, 774)
)
stroke(frontSheetPath, color: color(0xFFFFFF, 0.72), width: 1.5)

// Four abstract text lines. No letters or glyphs are used anywhere.
drawRoundedBar(x: 382, top: 354, width: 188, height: 20, color: color(0x173F47, 0.86))
drawRoundedBar(x: 382, top: 405, width: 274, height: 14, color: color(0x567779, 0.60))
drawRoundedBar(x: 382, top: 439, width: 226, height: 14, color: color(0x567779, 0.60))
drawRoundedBar(x: 382, top: 473, width: 260, height: 14, color: color(0x567779, 0.60))

// MARK: - Magnifier

let lensCenter = point(676, 614)
let handleStart = point(720, 658)
let handleEnd = point(824, 762)

var handleLine = CGMutablePath()
handleLine.move(to: handleStart)
handleLine.addLine(to: handleEnd)
let handleShape = handleLine.copy(strokingWithWidth: 48, lineCap: .round, lineJoin: .round, miterLimit: 10)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 22, color: color(0x00161B, 0.30))
fill(handleShape, with: color(0xE15B3C))
context.restoreGState()

fillLinearGradient(
    handleShape,
    colors: [color(0xFFAF6D), color(0xE85C3D)],
    locations: [0, 1],
    start: handleStart,
    end: handleEnd
)

// A soft highlight down the upper-left side of the handle.
let handleHighlight = CGMutablePath()
handleHighlight.move(to: CGPoint(x: handleStart.x - 8, y: handleStart.y + 8))
handleHighlight.addLine(to: CGPoint(x: handleEnd.x - 8, y: handleEnd.y + 8))
context.saveGState()
context.addPath(handleHighlight)
context.setStrokeColor(color(0xFFFFFF, 0.18))
context.setLineWidth(8)
context.setLineCap(.round)
context.strokePath()
context.restoreGState()

// Lens interior.
let lensFill = CGPath(ellipseIn: CGRect(
    x: lensCenter.x - 84,
    y: lensCenter.y - 84,
    width: 168,
    height: 168
), transform: nil)
fillLinearGradient(
    lensFill,
    colors: [color(0xFFFDF7), color(0xF8E9CE)],
    locations: [0, 1],
    start: CGPoint(x: lensCenter.x - 50, y: lensCenter.y + 78),
    end: CGPoint(x: lensCenter.x + 50, y: lensCenter.y - 78)
)

context.saveGState()
context.addPath(lensFill)
context.clip()
drawRoundedBar(x: 638, top: 574, width: 92, height: 10, color: color(0x1D4A50, 0.76))
drawRoundedBar(x: 638, top: 600, width: 68, height: 9, color: color(0x1D4A50, 0.70))
drawRoundedBar(x: 638, top: 624, width: 80, height: 9, color: color(0x1D4A50, 0.70))
drawRoundedBar(x: 638, top: 648, width: 52, height: 9, color: color(0x1D4A50, 0.62))

let lensReflection = CGMutablePath()
lensReflection.addArc(
    center: lensCenter,
    radius: 72,
    startAngle: 102 * .pi / 180,
    endAngle: 168 * .pi / 180,
    clockwise: false
)
context.addPath(lensReflection)
context.setStrokeColor(color(0xFFFFFF, 0.48))
context.setLineWidth(7)
context.setLineCap(.round)
context.strokePath()
context.restoreGState()

// Ring. The annulus is filled with a warm gradient and cast onto the papers.
let ringOuter = CGPath(ellipseIn: CGRect(
    x: lensCenter.x - 116,
    y: lensCenter.y - 116,
    width: 232,
    height: 232
), transform: nil)
let ringInner = CGPath(ellipseIn: CGRect(
    x: lensCenter.x - 82,
    y: lensCenter.y - 82,
    width: 164,
    height: 164
), transform: nil)
let ring = CGMutablePath()
ring.addPath(ringOuter)
ring.addPath(ringInner)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 20, color: color(0x00161B, 0.30))
context.addPath(ring)
context.setFillColor(color(0xE45B3C))
context.fillPath(using: .evenOdd)
context.restoreGState()

context.saveGState()
context.addPath(ring)
context.clip(using: .evenOdd)
let ringGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0xFFC27F), color(0xFF9A5A), color(0xDF5034)] as CFArray,
    locations: [0, 0.48, 1]
)!
context.drawLinearGradient(
    ringGradient,
    start: CGPoint(x: lensCenter.x - 90, y: lensCenter.y + 104),
    end: CGPoint(x: lensCenter.x + 94, y: lensCenter.y - 102),
    options: []
)
context.restoreGState()

// A narrow inner bevel and a top-left rim light finish the lens.
let innerBevel = CGPath(ellipseIn: CGRect(
    x: lensCenter.x - 82,
    y: lensCenter.y - 82,
    width: 164,
    height: 164
), transform: nil)
stroke(innerBevel, color: color(0x8F2C1B, 0.28), width: 3)

let outerRim = CGMutablePath()
outerRim.addArc(
    center: lensCenter,
    radius: 108,
    startAngle: 104 * .pi / 180,
    endAngle: 168 * .pi / 180,
    clockwise: false
)
context.saveGState()
context.addPath(outerRim)
context.setStrokeColor(color(0xFFE0B2, 0.44))
context.setLineWidth(4)
context.setLineCap(.round)
context.strokePath()
context.restoreGState()

context.restoreGState() // Composition translate

// MARK: - Save master

guard let image = context.makeImage() else {
    fatalError("Could not render the master image")
}

try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: readmeIconURL.deletingLastPathComponent(), withIntermediateDirectories: true)

guard let destination = CGImageDestinationCreateWithURL(
    readmeIconURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Could not create the master PNG destination")
}
CGImageDestinationAddImage(destination, image, [
    kCGImagePropertyPNGDictionary: [
        kCGImagePropertyPNGInterlaceType: 0
    ]
] as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write the master PNG")
}

func iconResourceName(base: Int, scale: Int) -> String {
    "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
}

// Every app icon is produced from the single README master below.
let masterSizeDestination = iconSetURL.appendingPathComponent(iconResourceName(base: 512, scale: 2))
if let existing = try? FileManager.default.contentsOfDirectory(
    at: iconSetURL,
    includingPropertiesForKeys: nil
) {
    for file in existing where file.pathExtension == "png" {
        try FileManager.default.removeItem(at: file)
    }
}
let sizes: [(base: Int, scale: Int)] = [
    (16, 1),
    (16, 2),
    (32, 1),
    (32, 2),
    (128, 1),
    (128, 2),
    (256, 1),
    (256, 2),
    (512, 1)
]

for entry in sizes {
    let pixels = entry.base * entry.scale
    let name = iconResourceName(base: entry.base, scale: entry.scale)
    let output = iconSetURL.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = [
        "-z", "\(pixels)", "\(pixels)",
        readmeIconURL.path,
        "--out", output.path
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("sips failed for \(name)")
    }
}

try FileManager.default.copyItem(at: readmeIconURL, to: masterSizeDestination)

print("Wrote icon master and \(sizes.count + 1) app icon resources.")

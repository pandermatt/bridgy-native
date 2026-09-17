import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the Bridgy app icon: blue has crossed top to bottom, and in doing so has
// cut red's left-to-right chain in half. That severing is the whole game.

let blue = CGColor(red: 0.427, green: 0.682, blue: 0.922, alpha: 1)
let red = CGColor(red: 1.0, green: 0.22, blue: 0.29, alpha: 1)

func render(size: CGFloat, rounded: Bool, to url: URL) {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    let full = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = rounded ? size * 0.085 : 0
    let plate = full.insetBy(dx: inset, dy: inset)

    context.saveGState()
    if rounded {
        let path = CGPath(roundedRect: plate, cornerWidth: plate.width * 0.22,
                          cornerHeight: plate.width * 0.22, transform: nil)
        context.addPath(path)
        context.clip()
    }

    // Deep navy backdrop, so the two chains carry the colour.
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.098, green: 0.153, blue: 0.267, alpha: 1),
            CGColor(red: 0.035, green: 0.055, blue: 0.106, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )

    let unit = plate.width
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: plate.minX + x * unit, y: plate.minY + (1 - y) * unit)
    }
    let stroke = unit * 0.105
    let dot = unit * 0.075

    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Red runs left to right but is severed in the middle.
    context.setStrokeColor(red)
    context.setLineWidth(stroke)
    context.strokeLineSegments(between: [point(0.11, 0.5), point(0.35, 0.5)])
    context.strokeLineSegments(between: [point(0.65, 0.5), point(0.89, 0.5)])

    // Blue runs the whole way, top to bottom, straight through the gap.
    context.setStrokeColor(blue)
    context.setLineWidth(stroke)
    context.strokeLineSegments(between: [point(0.5, 0.11), point(0.5, 0.89)])

    // Joints.
    context.setFillColor(red)
    for x: CGFloat in [0.11, 0.35, 0.65, 0.89] {
        let centre = point(x, 0.5)
        context.fillEllipse(in: CGRect(x: centre.x - dot / 2, y: centre.y - dot / 2, width: dot, height: dot))
    }
    context.setFillColor(blue)
    for y: CGFloat in [0.11, 0.5, 0.89] {
        let centre = point(0.5, y)
        context.fillEllipse(in: CGRect(x: centre.x - dot / 2, y: centre.y - dot / 2, width: dot, height: dot))
    }
    context.restoreGState()

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

render(size: 1024, rounded: false, to: outputDirectory.appendingPathComponent("icon-ios-1024.png"))
for size in [16, 32, 64, 128, 256, 512, 1024] {
    render(size: CGFloat(size), rounded: true, to: outputDirectory.appendingPathComponent("icon-mac-\(size).png"))
}
print("wrote icons to \(outputDirectory.path)")

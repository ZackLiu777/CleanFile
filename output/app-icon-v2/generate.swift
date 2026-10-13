// Reproducible flat vector artwork. No image input or external dependencies.
// Run: swift output/app-icon-v2/generate.swift output/app-icon-v2
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(String, [CGFloat], [CGFloat], [CGFloat])] = [
    ("Light", [0.696136474609375, 0.89813232421875, 1], [0.24, 0.37, 0.42], [0.16, 0.49, 0.65]),
    ("Dark", [0.07, 0.14, 0.18], [0.70, 0.90, 1], [0.36, 0.55, 0.61]),
    ("Tinted", [0, 0, 0], [0.98, 0.98, 0.98], [0.58, 0.58, 0.58])
]
let planes: [[CGPoint]] = [
    [(230,230),(742,230),(742,398),(398,398),(398,794),(230,794)].map { CGPoint(x: $0.0, y: $0.1) },
    [(454,454),(794,454),(794,622),(622,622),(622,794),(454,794)].map { CGPoint(x: $0.0, y: $0.1) }
]
for (name, background, primary, accent) in variants {
    guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                                  bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "IconRendering", code: 1)
    }
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(CGColor(red: background[0], green: background[1], blue: background[2], alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    if name == "Light" {
        let colors = [CGColor(red: background[0], green: background[1], blue: background[2], alpha: 1),
                      CGColor(red: 0.93, green: 0.98, blue: 1, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])
        }
    }
    for (points, color) in zip(planes, [primary, accent]) {
        context.setFillColor(CGColor(red: color[0], green: color[1], blue: color[2], alpha: 1))
        context.beginPath()
        context.addLines(between: points)
        context.closePath()
        context.fillPath()
    }
    let url = outputDirectory.appendingPathComponent("AppIcon_\(name)_NoAlpha_1024.png")
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconRendering", code: 2)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "IconRendering", code: 3) }
}

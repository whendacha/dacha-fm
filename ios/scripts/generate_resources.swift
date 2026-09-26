import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(NSColor(red: 0.055, green: 0.059, blue: 0.055, alpha: 1).cgColor)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let stops = [NSColor(red: 1, green: 0.81, blue: 0.54, alpha: 1).cgColor, NSColor(red: 0.98, green: 0.43, blue: 0.26, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: stops, locations: [0, 1])!
context.saveGState()
for (x, height) in [(230.0, 260.0), (360.0, 450.0), (490.0, 640.0), (620.0, 450.0), (750.0, 260.0)] {
    context.addPath(CGPath(roundedRect: CGRect(x: x - 44, y: 512 - height / 2, width: 88, height: height), cornerWidth: 44, cornerHeight: 44, transform: nil))
}
context.clip()
context.drawLinearGradient(gradient, start: CGPoint(x: 150, y: 850), end: CGPoint(x: 820, y: 170), options: [])
context.restoreGState()
let image = context.makeImage()!
let bitmap = NSBitmapImageRep(cgImage: image)
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)

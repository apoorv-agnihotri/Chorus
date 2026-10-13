import AppKit
import Foundation

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
func render(_ pixels: Int, to path: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 207, yRadius: 207)
    NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.96, alpha: 1).setFill(); background.fill()
    NSColor(calibratedRed: 0.05, green: 0.48, blue: 0.42, alpha: 1).setFill()
    let heights: [CGFloat] = [170, 350, 540, 410, 240]
    for (i, height) in heights.enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 239 + CGFloat(i) * 112, y: (1024 - height) / 2, width: 78, height: height), xRadius: 39, yRadius: 39).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
for size in [16, 32, 128, 256, 512] {
    try render(size, to: "\(output)/icon_\(size)x\(size).png")
    try render(size * 2, to: "\(output)/icon_\(size)x\(size)@2x.png")
}

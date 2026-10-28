import AppKit

@main struct MakeLimanIcon {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
                NSColor(srgbRed: 0.94, green: 0.97, blue: 0.98, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(pixels) * 0.04, dy: CGFloat(pixels) * 0.04), xRadius: CGFloat(pixels) * 0.2, yRadius: CGFloat(pixels) * 0.2).fill()
                NashiArtwork.draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()
                let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}

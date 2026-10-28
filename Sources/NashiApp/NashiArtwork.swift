import AppKit

/// Liman's independent geometric harbor mark. The internal type name is kept
/// for source compatibility; no upstream pear artwork is used at runtime.
enum NashiArtwork {
    static let gold = NSColor(srgbRed: 0.18, green: 0.57, blue: 0.67, alpha: 1)
    static let ink = NSColor(srgbRed: 0.08, green: 0.20, blue: 0.28, alpha: 1)
    static func draw(in rect: NSRect, happy: Bool = false, monochrome: Bool = false) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState(); defer { c.restoreGState() }
        c.translateBy(x: rect.minX, y: rect.minY); c.scaleBy(x: rect.width, y: rect.height)
        c.setStrokeColor((monochrome ? NSColor.black : gold).cgColor)
        c.setLineWidth(0.09); c.setLineCap(.round); c.setLineJoin(.round)
        c.move(to: CGPoint(x: 0.24, y: 0.77)); c.addLine(to: CGPoint(x: 0.24, y: 0.27))
        c.addLine(to: CGPoint(x: 0.77, y: 0.27)); c.strokePath()
        c.move(to: CGPoint(x: 0.49, y: 0.69)); c.addLine(to: CGPoint(x: 0.49, y: 0.48))
        c.addLine(to: CGPoint(x: 0.71, y: 0.48)); c.strokePath()
        c.setFillColor((monochrome ? NSColor.black : ink).cgColor)
        c.fillEllipse(in: CGRect(x: 0.65, y: 0.67, width: 0.12, height: 0.12))
    }
    static func mark(size: CGFloat, happy: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { draw(in: $0, happy: happy); return true }
    }
    static func menuIcon(updateAvailable: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { draw(in: $0, monochrome: true); return true }
        image.isTemplate = true; image.accessibilityDescription = "Liman"; return image
    }
}

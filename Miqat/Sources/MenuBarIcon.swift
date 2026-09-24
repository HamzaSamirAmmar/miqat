import AppKit

/// Monochrome mihrab-and-crescent glyph for the menu bar.
///
/// Drawn in code (rather than shipped as an asset) so it works for both the
/// Xcode and SwiftPM builds. Marked as a template so macOS tints it for
/// light/dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        // Artwork lives in a 1024-unit space; this is its tight bounding box.
        let art = CGRect(x: 210, y: 178, width: 604, height: 664)
        let height: CGFloat = 16
        let scale = height / art.height
        let size = NSSize(width: art.width * scale, height: height)

        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -art.minX, y: -art.minY)
            NSColor.black.set()

            // Pointed arch outline.
            let arch = NSBezierPath()
            arch.move(to: CGPoint(x: 252, y: 800))
            arch.line(to: CGPoint(x: 252, y: 510))
            arch.curve(to: CGPoint(x: 512, y: 220),
                       controlPoint1: CGPoint(x: 252, y: 394), controlPoint2: CGPoint(x: 338.7, y: 297.3))
            arch.curve(to: CGPoint(x: 772, y: 510),
                       controlPoint1: CGPoint(x: 685.3, y: 297.3), controlPoint2: CGPoint(x: 772, y: 394))
            arch.line(to: CGPoint(x: 772, y: 800))
            arch.close()
            arch.lineWidth = 84
            arch.lineJoinStyle = .round
            arch.stroke()

            // Crescent: a disc with an offset disc cut out of it.
            ctx.saveGState()
            let cut = CGPath(ellipseIn: CGRect(x: 556 - 92, y: 530 - 92, width: 184, height: 184), transform: nil)
            let clip = CGMutablePath()
            clip.addRect(art.insetBy(dx: -100, dy: -100))
            clip.addPath(cut)
            ctx.addPath(clip)
            ctx.clip(using: .evenOdd)
            ctx.fillEllipse(in: CGRect(x: 512 - 110, y: 560 - 110, width: 220, height: 220))
            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Miqat"
        return image
    }()
}

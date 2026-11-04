// Draws the app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024

func drawIcon() -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let context = NSGraphicsContext.current!.cgContext

        // macOS icon grid: 824pt body centered in 1024, continuous-corner squircle.
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
        context.saveGState()
        squircle.addClip()
        let background = NSGradient(colors: [
            NSColor(red: 0.07, green: 0.13, blue: 0.32, alpha: 1),
            NSColor(red: 0.10, green: 0.36, blue: 0.62, alpha: 1),
        ])!
        background.draw(in: body, angle: 70)

        // Rising earnings line across the lower part.
        let chart = NSBezierPath()
        chart.move(to: NSPoint(x: 170, y: 250))
        chart.line(to: NSPoint(x: 330, y: 330))
        chart.line(to: NSPoint(x: 450, y: 290))
        chart.line(to: NSPoint(x: 600, y: 410))
        chart.line(to: NSPoint(x: 720, y: 370))
        chart.line(to: NSPoint(x: 860, y: 500))
        chart.lineWidth = 26
        chart.lineCapStyle = .round
        chart.lineJoinStyle = .round
        NSColor(red: 0.36, green: 0.89, blue: 0.62, alpha: 0.9).setStroke()
        chart.stroke()
        context.restoreGState()

        func bubble(_ rect: CGRect, tailLeft: Bool) -> NSBezierPath {
            let path = NSBezierPath(roundedRect: rect, xRadius: 70, yRadius: 70)
            let tail = NSBezierPath()
            let x = tailLeft ? rect.minX + 70 : rect.maxX - 70
            tail.move(to: NSPoint(x: x - 40, y: rect.minY + 10))
            tail.line(to: NSPoint(x: x + (tailLeft ? -50 : 50), y: rect.minY - 70))
            tail.line(to: NSPoint(x: x + 40, y: rect.minY + 10))
            tail.close()
            path.append(tail)
            return path
        }

        func label(_ text: String, in rect: CGRect, size fontSize: CGFloat, color: NSColor, weight: NSFont.Weight) {
            let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let string = NSAttributedString(string: text, attributes: attributes)
            let bounds = string.size()
            string.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
        }

        // Back bubble: English source.
        let back = CGRect(x: 190, y: 560, width: 330, height: 250)
        NSColor(white: 1, alpha: 0.28).setFill()
        bubble(back, tailLeft: true).fill()
        label("A", in: back, size: 170, color: .white, weight: .bold)

        // Front bubble: Korean translation.
        let front = CGRect(x: 420, y: 430, width: 410, height: 310)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor.white.setFill()
        bubble(front, tailLeft: false).fill()
        NSGraphicsContext.restoreGraphicsState()
        label("가", in: front.offsetBy(dx: 0, dy: 6), size: 210, color: NSColor(red: 0.07, green: 0.15, blue: 0.38, alpha: 1), weight: .heavy)
        return true
    }
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let image = drawIcon()
for points in [16, 32, 128, 256, 512] {
    try png(image, pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(image, pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(image, pixels: 1024).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")

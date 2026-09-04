// Renders the Prompter app icon: a dark rounded square, two quiet lines of "text" and the
// Pace Dot resting under the bright one. Run via Scripts/make-icon.sh.
import AppKit

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let s = size
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let inset = rect.insetBy(dx: s * 0.06, dy: s * 0.06)
    let bg = CGPath(roundedRect: inset, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)

    // Background: deep graphite with a soft top light.
    ctx.addPath(bg); ctx.clip()
    let colors = [NSColor(calibratedWhite: 0.16, alpha: 1).cgColor, NSColor(calibratedWhite: 0.06, alpha: 1).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Lines: current phrase bright, next phrase subdued, both centred like the prompt.
    func line(y: CGFloat, width: CGFloat, height: CGFloat, alpha: CGFloat) {
        let r = CGRect(x: (s - width) / 2, y: y, width: width, height: height)
        ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: alpha).cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
        ctx.fillPath()
    }
    line(y: s * 0.60, width: s * 0.56, height: s * 0.085, alpha: 1.0)
    line(y: s * 0.47, width: s * 0.40, height: s * 0.085, alpha: 1.0)
    line(y: s * 0.27, width: s * 0.46, height: s * 0.07, alpha: 0.35)

    // Track and Pace Dot between the two blocks.
    let trackY = s * 0.395
    ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.14).cgColor)
    ctx.fill(CGRect(x: s * 0.22, y: trackY - s * 0.006, width: s * 0.56, height: s * 0.012))
    let dot = CGRect(x: s * 0.58, y: trackY - s * 0.035, width: s * 0.07, height: s * 0.07)
    ctx.setShadow(offset: .zero, blur: s * 0.04, color: NSColor(calibratedWhite: 1, alpha: 0.7).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: dot)
    image.unlockFocus()
    return image
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let img = render(size: CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
}
print("icon pngs written to \(out.path)")

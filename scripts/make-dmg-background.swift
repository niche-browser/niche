// Renders the DMG window background, resources/dmg/background.png: an 800x400 pt
// canvas at 2x (1600x800 px, 144 dpi) with the brand orange glowing in from the
// lower corners, the install line, and a chevron between the two icons.
// Layout must match resources/dmg/settings.py (icons centred at x 190 and 610).
//   swift scripts/make-dmg-background.swift
import Cocoa

let W: CGFloat = 800, H: CGFloat = 400, scale: CGFloat = 2

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let v = Int(hex.dropFirst(), radix: 16)!
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: alpha)
    }
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)  // points, so the PNG is written at 144 dpi
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

// Base: the same warm off-white Dia uses, so the white icon labels stay readable.
NSColor(hex: "#f7f7f6").setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Glows: soft radial blooms of the logo's signal orange, strongest bottom right, with a
// faint graphite shade top left so the off-white doesn't read flat.
// Coordinates are AppKit's, origin bottom left.
func glow(_ hex: String, at p: NSPoint, radius: CGFloat, alpha: CGFloat, squash: CGFloat = 1) {
    let c = NSColor(hex: hex)
    let g = NSGradient(colorsAndLocations: (c.withAlphaComponent(alpha), 0),
                       (c.withAlphaComponent(alpha * 0.45), 0.45),
                       (c.withAlphaComponent(0), 1))!
    cg.saveGState()
    cg.translateBy(x: p.x, y: p.y)
    cg.scaleBy(x: 1, y: squash)
    g.draw(fromCenter: .zero, radius: 0, toCenter: .zero, radius: radius, options: [])
    cg.restoreGState()
}
glow("#f45120", at: NSPoint(x: W - 30, y: -70), radius: 420, alpha: 0.30, squash: 0.55)
glow("#ff9a6b", at: NSPoint(x: 60, y: -80), radius: 360, alpha: 0.16, squash: 0.5)
glow("#16181b", at: NSPoint(x: -20, y: H + 20), radius: 260, alpha: 0.06, squash: 0.8)

// Install line: "To install, drag Niche to Applications", names in bold.
let size: CGFloat = 17
let grey = NSColor(hex: "#1d1d1f", alpha: 0.6), ink = NSColor(hex: "#1d1d1f")
let regular = NSFont.systemFont(ofSize: size, weight: .regular)
let bold = NSFont.systemFont(ofSize: size, weight: .semibold)
let line = NSMutableAttributedString()
for (text, strong) in [("To install, drag ", false), ("Niche", true), (" to ", false), ("Applications", true)] {
    line.append(NSAttributedString(string: text, attributes: [
        .font: strong ? bold : regular, .foregroundColor: strong ? ink : grey, .kern: -0.1,
    ]))
}
let textSize = line.size()
line.draw(at: NSPoint(x: (W - textSize.width) / 2, y: H - 53 - textSize.height / 2))

// Chevrons: three, fading in toward Applications, centred between the icons.
let chevronY = H - 193, step: CGFloat = 16.5, half: CGFloat = 10
for (i, alpha) in [0.22, 0.5, 1.0].enumerated() {
    let x = W / 2 - step + CGFloat(i) * step
    let p = NSBezierPath()
    p.move(to: NSPoint(x: x - 4.5, y: chevronY + half))
    p.line(to: NSPoint(x: x + 4.5, y: chevronY))
    p.line(to: NSPoint(x: x - 4.5, y: chevronY - half))
    p.lineWidth = 3.4
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    ink.withAlphaComponent(alpha).setStroke()
    p.stroke()
}

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "resources/dmg/background.png")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")

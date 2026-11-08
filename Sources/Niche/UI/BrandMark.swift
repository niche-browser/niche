import SwiftUI

/// The Niche mark from brand/niche-mark.svg, rendered by scripts/make-brand.swift
/// into resources/brand.
struct BrandMark: View {
    var size: CGFloat = 48
    var mono = false

    private static let colour: NSImage? = load("niche-mark@2x")
    private static let monoImage: NSImage? = load("niche-mark-mono")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "brand") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        if let img = mono ? BrandMark.monoImage : BrandMark.colour {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityLabel("Niche")
        }
    }
}

/// The bare mark drawn as vectors (brand/niche-mark-mono.svg's geometry on its 32 grid): the
/// arch in the ink colour, the dot in the signal orange. Crisp at any size, light or dark.
struct BrandGlyph: View {
    var size: CGFloat = 40
    var ink: Color = .primary

    var body: some View {
        Canvas { ctx, canvas in
            let s = canvas.width / 32
            var arch = Path()
            arch.move(to: CGPoint(x: 7 * s, y: 17.5 * s))
            arch.addLine(to: CGPoint(x: 7 * s, y: 15 * s))
            arch.addArc(center: CGPoint(x: 16 * s, y: 15 * s), radius: 9 * s,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            arch.addLine(to: CGPoint(x: 25 * s, y: 29 * s))
            ctx.stroke(arch, with: .color(ink), lineWidth: 6 * s)
            ctx.fill(Path(ellipseIn: CGRect(x: 2.5 * s, y: 20 * s, width: 9 * s, height: 9 * s)), with: .color(Design.accent))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Niche")
    }
}

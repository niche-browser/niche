import Foundation

/// The colour a page shows along its top edge, which the bar above it takes so the two read as
/// one surface. Read from what the page drew (a strip of pixels across its top), not from what
/// it says about itself: a `theme-color` meta is a brand colour as often as the page's, and the
/// element under one point misses a header that is a gradient or a picture. 13 Nov 2026: on
/// amsterdam-dance-event.nl (black, a yellow glow in the middle) the bar was light grey; Dia's was
/// black.
public enum PageTopColor {
    public struct RGB: Equatable, Hashable, Sendable {
        public var r: UInt8, g: UInt8, b: UInt8

        public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
            (self.r, self.g, self.b) = (r, g, b)
        }

        /// "#RRGGBB".
        public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

        /// From "#RRGGBB"; nil for anything else.
        public init?(hex: String) {
            var s = hex.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
            self.init(UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
        }
    }

    /// Pixels this close on every channel are one colour (antialiasing, a JPEG's noise).
    public static let tolerance = 10
    /// The share of the strip one colour needs to be the page's top edge: nearly all of it. A
    /// glow or a picture can hold most of an edge and still sit on another ground.
    public static let plain = 0.8

    /// A colour read from a picture of the page is a step or two off what the page asked for
    /// (the picture is compressed). When it is within `tolerance` of a colour the page named (its
    /// ground, its top element's), that exact one is meant; the nearest of them is the answer.
    public static func settled(_ read: RGB, named: [RGB]) -> RGB {
        func distance(_ c: RGB) -> Int { max(abs(Int(c.r) - Int(read.r)), abs(Int(c.g) - Int(read.g)), abs(Int(c.b) - Int(read.b))) }
        guard let nearest = named.min(by: { distance($0) < distance($1) }), distance(nearest) <= tolerance else { return read }
        return nearest
    }

    /// The bar's colour. `pixels` run across the page's top edge; `background` is the page's own
    /// ground (its body or root colour), nil when it has none.
    /// - One colour across nearly all of the edge is the edge: a header bar, a plain page.
    /// - A gradient or a picture has no such colour: the page's ground then, which is what shows
    ///   where the picture ends.
    /// - Without a ground, the colour most of the edge has.
    public static func color(pixels: [RGB], background: RGB?) -> RGB? {
        guard !pixels.isEmpty else { return background }
        // How much of the edge each colour on it has, its near neighbours counted with it.
        var counts: [RGB: Int] = [:]
        for p in pixels { counts[p, default: 0] += 1 }
        func near(_ a: RGB, _ b: RGB) -> Bool {
            abs(Int(a.r) - Int(b.r)) <= tolerance && abs(Int(a.g) - Int(b.g)) <= tolerance && abs(Int(a.b) - Int(b.b)) <= tolerance
        }
        var best: (color: RGB, share: Int)?
        // In the strip's order, so of two colours with the same share the leftmost wins.
        var seen: Set<RGB> = []
        for candidate in pixels where seen.insert(candidate).inserted {
            let share = counts.reduce(0) { $0 + (near(candidate, $1.key) ? $1.value : 0) }
            if best.map({ share > $0.share }) ?? true { best = (candidate, share) }
        }
        guard let best else { return background }
        // Of the colours that count as that one, the one drawn most: the header's own colour,
        // not a pixel of its antialiased edge.
        var drawn = best.color
        for p in pixels where near(best.color, p) && counts[p]! > counts[drawn]! { drawn = p }
        if Double(best.share) >= plain * Double(pixels.count) { return drawn }
        return background ?? drawn
    }
}

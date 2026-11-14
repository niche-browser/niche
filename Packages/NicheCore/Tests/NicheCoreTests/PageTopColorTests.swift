import NicheCore
import Testing

/// The bar takes the colour the page drew along its top edge (13 Nov 2026).
struct PageTopColorTests {
    typealias RGB = PageTopColor.RGB
    private let black = RGB(0, 0, 0), white = RGB(255, 255, 255), olive = RGB(170, 175, 60)

    @Test func aPlainEdgeIsItsColour() {
        #expect(PageTopColor.color(pixels: Array(repeating: RGB(15, 15, 15), count: 64), background: white) == RGB(15, 15, 15))
    }

    /// A header bar with a logo and a button reaching its top: nearly all of the edge is still the bar.
    @Test func aHeaderWithThingsInIt() {
        let strip = Array(repeating: RGB(36, 41, 47), count: 56) + Array(repeating: white, count: 5) + Array(repeating: RGB(45, 164, 78), count: 3)
        #expect(PageTopColor.color(pixels: strip, background: white) == RGB(36, 41, 47))
    }

    /// A glow that covers two thirds of the edge is still a picture on the page's ground, not the
    /// page's colour: amsterdam-dance-event.nl's yellow came out as the bar's while its left end
    /// was black (13 Nov 2026).
    @Test func aWideGlowIsNotTheEdge() {
        let strip = Array(repeating: black, count: 12) + Array(repeating: RGB(60, 62, 20), count: 8) + Array(repeating: olive, count: 44)
        #expect(PageTopColor.color(pixels: strip, background: black) == black)
    }

    /// Antialiasing and noise: neighbours a few steps apart are one colour, and the answer is one of them.
    @Test func nearlyTheSameCountsAsTheSame() {
        var strip: [RGB] = []
        for i in 0..<64 {
            let r = UInt8(14 + i % 3), g = UInt8(15 + i % 2)
            strip.append(RGB(r, g, 16))
        }
        let c = PageTopColor.color(pixels: strip, background: white)
        #expect(c.map { strip.contains($0) } == true)
    }

    /// amsterdam-dance-event.nl: black at the left running into a yellow glow. No colour holds
    /// half the edge, so the page's ground (black) is the bar's, as in Dia.
    @Test func aGradientGivesThePagesGround() {
        var strip = Array(repeating: black, count: 14)
        for i in 0..<50 {
            let r = UInt8(i * 170 / 49), g = UInt8(i * 175 / 49), b = UInt8(i * 60 / 49)
            strip.append(RGB(r, g, b))
        }
        #expect(PageTopColor.color(pixels: strip, background: black) == black)
        // The same picture on a page with no ground of its own: what most of the edge shows.
        #expect(PageTopColor.color(pixels: strip, background: nil) == black)
    }

    /// A photograph across the top of a white page.
    @Test func aPictureGivesThePagesGround() {
        var strip: [RGB] = []
        for i in 0..<64 {
            let r = UInt8((i * 37) % 256), g = UInt8((i * 91) % 256), b = UInt8((i * 53) % 256)
            strip.append(RGB(r, g, b))
        }
        #expect(PageTopColor.color(pixels: strip, background: white) == white)
    }

    @Test func nothingDrawnNothingKnown() {
        #expect(PageTopColor.color(pixels: [], background: nil) == nil)
        #expect(PageTopColor.color(pixels: [], background: olive) == olive)
    }

    /// A screenshot's #0E0F10 for a page that asked for #0F0F0F: the page's own value is the bar's.
    @Test func aReadColourSettlesOnTheOneThePageNamed() {
        #expect(PageTopColor.settled(RGB(14, 15, 16), named: [white, RGB(15, 15, 15)]) == RGB(15, 15, 15))
        #expect(PageTopColor.settled(RGB(14, 15, 16), named: [RGB(20, 20, 20), RGB(15, 15, 15)]) == RGB(15, 15, 15))
        // Nothing named is near: what was read stands.
        #expect(PageTopColor.settled(RGB(36, 41, 47), named: [white, black]) == RGB(36, 41, 47))
        #expect(PageTopColor.settled(RGB(36, 41, 47), named: []) == RGB(36, 41, 47))
    }

    @Test func hex() {
        #expect(RGB(15, 15, 15).hex == "#0F0F0F")
        #expect(RGB(hex: "#aaaf3c") == olive)
        #expect(RGB(hex: "rgb(1, 2, 3)") == nil)
    }
}

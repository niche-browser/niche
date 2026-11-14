import CoreGraphics
import NicheCore
import Testing

/// An extension's popup opens beside its button, inside the window (13 Nov 2026).
struct ExtensionPopupPlacementTests {
    let window: ClosedRange<CGFloat> = 300...1700
    let screen: ClosedRange<CGFloat> = 0...2056

    /// A toolbar button at the window's right: the popup's right edge is the button's, as in Chrome.
    @Test func hangsFromItsButtonsRightEdge() {
        #expect(ExtensionPopupPlacement.minX(anchorX: 1660, width: 380, window: window, screen: screen) == 1280)
    }

    /// A pin in the sidebar, 259 pt into the window: a 380 pt popup started 121 pt left of the
    /// window. It opens just inside the window instead, under its button's row.
    @Test func aSidebarPinsPopupStaysInTheWindow() {
        #expect(ExtensionPopupPlacement.minX(anchorX: 300 + 259, width: 380, window: window, screen: screen) == 308)
        // The first cell of the pin grid, 80 pt in, and a popup that grew to 800 pt after loading.
        #expect(ExtensionPopupPlacement.minX(anchorX: 300 + 80, width: 800, window: window, screen: screen) == 308)
        // A narrow popup fits to the left of its button's right edge: nothing changes.
        #expect(ExtensionPopupPlacement.minX(anchorX: 300 + 259, width: 200, window: window, screen: screen) == 359)
    }

    /// A window flush with the screen's left edge keeps the popup on the screen too.
    @Test func staysOnTheScreen() {
        #expect(ExtensionPopupPlacement.minX(anchorX: 259, width: 380, window: 0...1400, screen: screen) == 8)
        #expect(ExtensionPopupPlacement.minX(anchorX: 2050, width: 380, window: 700...2100, screen: screen) == 1668)
    }

    /// A popup wider than the window can't fit in it: it keeps its button's right edge, on screen.
    @Test func widerThanTheWindow() {
        #expect(ExtensionPopupPlacement.minX(anchorX: 900, width: 800, window: 500...1000, screen: screen) == 100)
    }

    /// Dragging moves this popup; it only has to stay on the screen.
    @Test func aDraggedPopupGoesWhereItWasDropped() {
        #expect(ExtensionPopupPlacement.minX(anchorX: 1660, width: 380, dragged: -1100, window: window, screen: screen) == 180)
        #expect(ExtensionPopupPlacement.minX(anchorX: 1660, width: 380, dragged: -3000, window: window, screen: screen) == 8)
    }

    @Test func withoutAWindowOrScreenItHangsFromTheAnchor() {
        #expect(ExtensionPopupPlacement.minX(anchorX: 500, width: 380, window: nil, screen: nil) == 120)
    }
}

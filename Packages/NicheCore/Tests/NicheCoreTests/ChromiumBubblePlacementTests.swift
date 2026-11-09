import CoreGraphics
import NicheCore
import Testing

/// Chromium's "extension added" bubble hung half off the screen's left edge (anchored to the
/// page's hidden toolbar, at the screen's corner).
struct ChromiumBubblePlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
    let window = CGRect(x: 0, y: 74, width: 2056, height: 1216)

    @Test func aBubbleOffTheScreenMovesInsideItsWindow() throws {
        let bubble = CGRect(x: -224, y: 1158, width: 448, height: 132)
        let moved = try #require(ChromiumBubblePlacement.frame(for: bubble, window: window, screens: [screen]))
        #expect(moved == CGRect(x: 8, y: 1150, width: 448, height: 132))
        #expect(screen.contains(moved))
    }

    @Test func bubblesChromiumPlacedOnAScreenStay() {
        // An autofill list below a field may overhang the window; it is still on the screen.
        let autofill = CGRect(x: 600, y: 20, width: 300, height: 200)
        #expect(ChromiumBubblePlacement.frame(for: autofill, window: window, screens: [screen]) == nil)
        // On a second screen.
        let second = CGRect(x: 2056, y: 0, width: 1920, height: 1080)
        #expect(ChromiumBubblePlacement.frame(for: CGRect(x: 2500, y: 100, width: 300, height: 100),
                                              window: window, screens: [screen, second]) == nil)
    }
}

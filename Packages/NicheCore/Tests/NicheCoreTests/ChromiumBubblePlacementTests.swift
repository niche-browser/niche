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

/// Chromium hangs its extension dialogs ("Add …?", "… has been added", "Remove …?") from the
/// page's hidden toolbar, whose buttons all sit at the page's top-left corner: one went off the
/// screen's left edge, the next dropped over the page's top left. They open at the page's top
/// right instead, where Chrome's extensions button is, every time.
struct ChromiumToolbarDialogPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    // The page right of a 240 pt sidebar, under the menu bar (AppKit's y runs up).
    let page = CGRect(x: 240, y: 10, width: 1478, height: 1050)

    @Test func theAddedBubbleOffTheLeftEdgeOpensAtThePagesTopRight() throws {
        let added = CGRect(x: -180, y: 1060 - 132, width: 420, height: 132)
        let moved = try #require(ChromiumBubblePlacement.toolbarDialogFrame(for: added, page: page))
        #expect(moved == CGRect(x: 1718 - 10 - 420, y: 1060 - 10 - 132, width: 420, height: 132))
    }

    @Test func theRemoveDialogUnderTheTopLeftMovesThereToo() throws {
        let remove = CGRect(x: 242, y: 1060 - 44 - 214, width: 353, height: 214)
        let moved = try #require(ChromiumBubblePlacement.toolbarDialogFrame(for: remove, page: page))
        #expect(moved.maxX == page.maxX - 10)
        #expect(moved.maxY == page.maxY - 10)
    }

    @Test func theRemoveDialogFromTheWebStoreMovesThere() throws {
        // Measured in NicheDev, 9 Nov 2026: the page host {{244, 74}, {1812, 1216}}, and Chromium's
        // "Remove …?" 172 pt in from its left (the hidden toolbar's extensions area) and 40 pt down.
        let host = CGRect(x: 244, y: 74, width: 1812, height: 1216)
        let remove = CGRect(x: 416, y: 1056, width: 320, height: 194)
        let moved = try #require(ChromiumBubblePlacement.toolbarDialogFrame(for: remove, page: host))
        #expect(moved == CGRect(x: 2056 - 10 - 320, y: 1290 - 10 - 194, width: 320, height: 194))
    }

    @Test func theAddedBubbleMeasuredInNicheDevMovesThere() throws {
        // 9 Nov 2026: a titled window with no parent, shown centred {{804, 887}, {448, 132}} and
        // then moved by Chromium to x −224 at the page's top.
        let host = CGRect(x: 244, y: 74, width: 1812, height: 1216)
        #expect(ChromiumBubblePlacement.toolbarDialogFrame(for: CGRect(x: 804, y: 887, width: 448, height: 132), page: host) == nil)
        let moved = try #require(ChromiumBubblePlacement.toolbarDialogFrame(for: CGRect(x: -224, y: 1158, width: 448, height: 132), page: host))
        #expect(moved == CGRect(x: 2056 - 10 - 448, y: 1290 - 10 - 132, width: 448, height: 132))
    }

    @Test func aSitesAlertCentredAtTheTopOfANarrowPageStays() {
        // Chrome hangs a page's alert() from the top of the page, centred.
        let narrow = CGRect(x: 240, y: 10, width: 700, height: 1050)
        let alert = CGRect(x: 240 + 350 - 225, y: 1060 - 150, width: 450, height: 150)
        #expect(ChromiumBubblePlacement.toolbarDialogFrame(for: alert, page: narrow) == nil)
    }

    @Test func dialogsElsewhereStayWhereChromiumPutThem() {
        // Centred on the page (a tab-modal dialog), and one already in place.
        #expect(ChromiumBubblePlacement.toolbarDialogFrame(for: CGRect(x: 800, y: 400, width: 400, height: 200), page: page) == nil)
        let placed = CGRect(x: 1718 - 10 - 420, y: 1060 - 10 - 132, width: 420, height: 132)
        #expect(ChromiumBubblePlacement.toolbarDialogFrame(for: placed, page: page) == nil)
        // Hanging from the top but well right of the corner: something on the page anchored it.
        #expect(ChromiumBubblePlacement.toolbarDialogFrame(for: CGRect(x: 760, y: 900, width: 300, height: 150), page: page) == nil)
    }

    @Test func aDialogWiderThanThePageKeepsItsLeftEdgeOnThePage() throws {
        let narrow = CGRect(x: 240, y: 10, width: 300, height: 1050)
        let moved = try #require(ChromiumBubblePlacement.toolbarDialogFrame(for: CGRect(x: -100, y: 900, width: 420, height: 150), page: narrow))
        #expect(moved.minX == narrow.minX)
    }
}

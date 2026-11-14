import NicheCore
import Testing

/// Add Split View opens an empty pane with the command bar; the row picked there fills that pane
/// (13 Nov 2026: a favorite's row switched to the favorite and left the pane empty).
struct SplitPaneFillTests {
    @Test func anOpenTabOfThisSpaceJoinsTheSplit() {
        #expect(SplitPaneFill.fill(paneOfThisSplit: false, pinned: false, sameSpace: true) == .joins)
    }

    @Test func aFavoriteOrPinnedTabStaysAndItsPageOpensInThePane() {
        #expect(SplitPaneFill.fill(paneOfThisSplit: false, pinned: true, sameSpace: true) == .opensAddress)
    }

    @Test func aTabOfAnotherSpaceStaysThere() {
        #expect(SplitPaneFill.fill(paneOfThisSplit: false, pinned: false, sameSpace: false) == .opensAddress)
    }

    @Test func theRowSaysWhatItDoes() {
        #expect(SplitPaneFill.rowHint(fillingPane: true) == "Open in Split")
        #expect(SplitPaneFill.rowHint(fillingPane: false) == "Switch to Tab")
    }

    @Test func aPaneAlreadyInTheSplitOpensASecondTime() {
        #expect(SplitPaneFill.fill(paneOfThisSplit: true, pinned: false, sameSpace: true) == .opensAddress)
    }
}

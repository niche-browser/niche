import CoreGraphics
import NicheCore
import Testing

/// The downloads list over the Library button and the sidebar player share the bottom of the
/// sidebar. On 21 Nov 2026 the list opened above the player's cards: reaching a row meant crossing
/// the player, whose cards then opened under the list, and the rows' names were drawn over them.
struct SidebarBottomTests {
    /// Two cards at rest (48 pt) and two downloads (a 128 pt list) in a column whose list area ends at 800.
    private func bottom(open: Bool, rest: CGFloat = 48, tray: CGFloat = 128) -> SidebarBottom {
        SidebarBottom(areaBottom: 800, playerRest: rest, trayHeight: tray, trayOpen: open, buttonTop: 816)
    }

    /// The list keeps the pointer from the Library button up to its rows: the gap between them is
    /// the list's too. A slow move took longer to cross it than the list waits before closing
    /// (22 Nov 2026), and the list was gone before the pointer reached a row.
    @Test func theListsHoverReachesTheLibraryButton() {
        let b = bottom(open: true)
        #expect(b.trayHoverBottom == 816)
        #expect(b.trayHoverBottom >= b.trayBottom)
        // A button higher than the list's bottom (never in the sidebar) doesn't shorten the list.
        let high = SidebarBottom(areaBottom: 800, playerRest: 48, trayHeight: 128, trayOpen: true, buttonTop: 790)
        #expect(high.trayHoverBottom == 800)
    }

    /// The list opens right over the Library button, where the player rests, so the pointer
    /// never crosses the player on its way from the button to a row.
    @Test func downloadsOpenWhereThePlayerRests() {
        let b = bottom(open: true)
        #expect(b.trayBottom == 800)
        #expect(b.trayTop == 672)
        // The tab list still ends over the resting player: opening the list moves nothing.
        #expect(b.listBottom == 752)
        #expect(bottom(open: false).listBottom == 752)
    }

    /// While the list is open it owns the bottom: the player fades with the tab list behind it and
    /// its cards don't open under the pointer, so the list's rows never sit on a card.
    @Test func thePlayerGivesWayWhileTheListIsOpen() {
        let open = bottom(open: true)
        #expect(!open.playerShown)
        #expect(!open.playerTakesHover)
        let closed = bottom(open: false)
        #expect(closed.playerShown)
        #expect(closed.playerTakesHover)
    }

    /// No player: the list ends where the list area does, as before.
    @Test func withoutAPlayer() {
        let b = bottom(open: true, rest: 0)
        #expect(b.listBottom == 800)
        #expect(b.trayBottom == 800)
        #expect(b.trayTop == 672)
    }
}

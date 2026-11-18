import Foundation
import Testing
@testable import NicheCore

/// The tab strip across the top of a window: where its items go as the window narrows.
struct TabStripLayoutTests {
    typealias Item = TabStripLayout.Item
    let m = TabStripLayout.Metrics()

    private func tabs(_ n: Int) -> [Item] { (0..<n).map { _ in .tab(UUID()) } }

    @Test func aFewTabsKeepTheirFullWidthAndThePlusFollowsTheLast() {
        let items: [Item] = [.space] + tabs(3)
        let r = TabStripLayout.layout(items, width: 1200)
        #expect(r.tabWidth == 200)
        #expect(r.titled)
        #expect(!r.scrolls)
        // The chip, its gap, then the run.
        #expect(r.fixed.map(\.x) == [0])
        #expect(r.runX == 30)
        #expect(r.run.map(\.x) == [0, 202, 404])
        #expect(r.runContentWidth == 604)
        #expect(r.plusX == 30 + 604 + 4)
    }

    @Test func favoritesAndTheRuleStandBeforeTheRun() {
        let items: [Item] = [.space, .favorite(UUID()), .favorite(UUID()), .rule] + tabs(1)
        let r = TabStripLayout.layout(items, width: 1200)
        #expect(r.fixed.map(\.x) == [0, 30, 60, 90])
        #expect(r.fixed.map(\.width) == [28, 28, 28, 13])
        #expect(r.runX == 103)
    }

    @Test func tabsShareTheRoomEvenlyWhenItRunsShort() {
        // 620 of room: 30 for the chip, 32 for the plus, 558 for five tabs and four gaps.
        let r = TabStripLayout.layout([.space] + tabs(5), width: 620)
        #expect(r.tabWidth == 110)
        #expect(r.titled)
        #expect(!r.scrolls)
        #expect(Set(r.run.map(\.width)) == [110])
    }

    @Test func narrowTabsLoseTheirTitlesThenScroll() {
        let narrow = TabStripLayout.layout([.space] + tabs(10), width: 620)
        // (558 - 18) / 10 = 54: under the titled width, over the minimum.
        #expect(narrow.tabWidth == 54)
        #expect(!narrow.titled)
        #expect(!narrow.scrolls)

        let crowded = TabStripLayout.layout([.space] + tabs(30), width: 620)
        #expect(crowded.tabWidth == 40)
        #expect(crowded.scrolls)
        #expect(crowded.runContentWidth == 30 * 40 + 29 * 2)
        #expect(crowded.runVisibleWidth == 558)
        // The New Tab button stays at the run's edge instead of scrolling away.
        #expect(crowded.plusX == 30 + 558 + 4)
        #expect(crowded.maxScroll == 1258 - 558)
    }

    @Test func aSplitIsWiderThanATabAndAGroupNameKeepsItsOwnWidth() {
        let split = UUID(), group = UUID()
        let items: [Item] = [.group(group, width: 64), .tab(UUID()), .split(split, panes: 2), .split(UUID(), panes: 3)]
        let r = TabStripLayout.layout(items, width: 2000)
        #expect(r.run.map(\.width) == [64, 200, 300, 380])

        // Short of room, the name keeps its width and the rest shrink together.
        let tight = TabStripLayout.layout(items, width: 32 + 64 + 3 * 2 + 4.4 * 100 + 1)
        #expect(tight.tabWidth == 100)
        #expect(tight.run.map(\.width) == [64, 100, 150, 190])
    }

    @Test func tabsDoNotWidenWhileThePointerIsStillInTheStrip() {
        // Six tabs at 110 each; one closes. Free to settle they would widen to 132.
        let after = [Item.space] + tabs(5)
        #expect(TabStripLayout.layout([Item.space] + tabs(6), width: 734).tabWidth == 110)
        #expect(TabStripLayout.layout(after, width: 734).tabWidth == 132)
        let held = TabStripLayout.layout(after, width: 734, heldTabWidth: 110)
        #expect(held.tabWidth == 110)
        // Holding never widens a tab past what the room gives.
        #expect(TabStripLayout.layout(after, width: 400, heldTabWidth: 200).tabWidth == 66)
    }

    @Test func anEmptyStripPutsThePlusWhereTheFirstTabWouldBe() {
        let r = TabStripLayout.layout([.space], width: 900)
        #expect(r.run.isEmpty)
        #expect(r.plusX == 30)
        #expect(!r.scrolls)
    }

    @Test func scrollingBringsATabIntoViewWithAPeekOfTheNext() {
        let all = tabs(30)
        let r = TabStripLayout.layout(all, width: 632)
        // Tab 0 shows already.
        #expect(TabStripLayout.scroll(toShow: all[0].id!, in: r, offset: 0) == 0)
        // Tab 20 starts at 840 and ends at 880: its end and 24 pt more come into view.
        #expect(TabStripLayout.scroll(toShow: all[20].id!, in: r, offset: 0) == 880 + 24 - 600)
        // Scrolled far along, going back to tab 2 (at 84) shows 24 pt before it.
        #expect(TabStripLayout.scroll(toShow: all[2].id!, in: r, offset: 500) == 60)
        // Never past either end.
        #expect(TabStripLayout.scroll(toShow: all[29].id!, in: r, offset: 0) == r.maxScroll)
        #expect(TabStripLayout.scroll(toShow: all[0].id!, in: r, offset: 300) == 0)
    }

    @Test func aDraggedTabPassesItsNeighboursAtTheirMiddles() {
        let all = tabs(4)
        let r = TabStripLayout.layout(all, width: 2000)
        let moving = all[0].id!
        // Its own slot: nothing passed.
        #expect(TabStripLayout.insertionIndex(x: 100, among: r.run, moving: moving) == 0)
        // Just short of the second tab's middle (302), then past it.
        #expect(TabStripLayout.insertionIndex(x: 301, among: r.run, moving: moving) == 0)
        #expect(TabStripLayout.insertionIndex(x: 303, among: r.run, moving: moving) == 1)
        #expect(TabStripLayout.insertionIndex(x: 5000, among: r.run, moving: moving) == 3)
        // A tab from somewhere else counts every tab.
        #expect(TabStripLayout.insertionIndex(x: 5000, among: r.run, moving: nil) == 4)
    }
}

/// The bookmarks bar: what fits, and what goes behind the chevron.
struct BookmarksBarLayoutTests {
    @Test func everythingShowsWhenItFits() {
        #expect(BookmarksBarLayout.visibleCount(widths: [80, 90, 100], gap: 2, available: 274, chevron: 24) == 3)
        #expect(BookmarksBarLayout.visibleCount(widths: [], gap: 2, available: 100, chevron: 24) == 0)
    }

    @Test func whatDoesNotFitLeavesRoomForTheChevron() {
        // 274 would hold all three; 273 holds two and the chevron (24 + 82 + 92 = 198).
        #expect(BookmarksBarLayout.visibleCount(widths: [80, 90, 100], gap: 2, available: 273, chevron: 24) == 2)
        #expect(BookmarksBarLayout.visibleCount(widths: [80, 90, 100], gap: 2, available: 110, chevron: 24) == 1)
        #expect(BookmarksBarLayout.visibleCount(widths: [80, 90, 100], gap: 2, available: 60, chevron: 24) == 0)
    }

    @Test func aDropLandsBeforeTheFirstItemPastThePointer() {
        let frames: [(x: Double, width: Double)] = [(0, 80), (82, 90), (174, 100)]
        #expect(BookmarksBarLayout.insertionIndex(x: 10, frames: frames) == 0)
        #expect(BookmarksBarLayout.insertionIndex(x: 41, frames: frames) == 1)
        #expect(BookmarksBarLayout.insertionIndex(x: 130, frames: frames) == 2)
        #expect(BookmarksBarLayout.insertionIndex(x: 900, frames: frames) == 3)
    }
}

/// Where the tabs are is a setting; the bars that go with it follow.
struct WindowLayoutSettingsTests {
    @Test func theSidebarIsTheDefaultAndOldSettingsKeepIt() throws {
        #expect(AppSettings().windowLayout == .sidebar)
        #expect(AppSettings().showBookmarksBar)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"toolbarDefaultMigrated": true, "showToolbar": true}"#.utf8))
        #expect(old.windowLayout == .sidebar)
        #expect(old.showBookmarksBar)
        // A layout a later version saved reads as the sidebar instead of failing the file.
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"windowLayout": "bottom"}"#.utf8))
        #expect(unknown.windowLayout == .sidebar)
    }

    @Test func theLayoutSurvivesASave() throws {
        var s = AppSettings()
        s.windowLayout = .top
        s.showBookmarksBar = false
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.windowLayout == .top)
        #expect(!back.showBookmarksBar)
    }

    @Test func tabsOnTopBringTheirOwnBarSoThePageCarriesNone() {
        var s = AppSettings()
        #expect(!s.toolbarShown)
        #expect(!s.showsBar(above: "https://example.com"))
        s.showToolbar = true
        #expect(s.toolbarShown)
        #expect(s.showsBar(above: "https://example.com"))
        s.windowLayout = .top
        s.showToolbar = false
        #expect(s.toolbarShown)
        // The bar is the window's, above every pane: a page's card has none, a developer site's too.
        #expect(!s.showsBar(above: "https://example.com"))
        #expect(!s.showsBar(above: "http://localhost:3000"))
    }
}

@Suite struct TitleRowHoldTests {
    @Test func aNeighbourPassingUnderACarriedTabLeavesTheWindowHeld() {
        // 17 Nov 2026: a tab was dropped and pressed again without the pointer leaving it, and the
        // window went with it. While it was carried a neighbour stepped under the pointer and
        // away again, and its leaving let the window go though the pointer was still on the tab.
        var hold = TitleRowHold()
        let carried = UUID(), neighbour = UUID()
        hold.set(carried, inside: true)
        hold.set(neighbour, inside: true)
        hold.set(neighbour, inside: false)
        #expect(hold.holdsWindow)
        hold.set(carried, inside: false)
        #expect(!hold.holdsWindow)
    }

    @Test func leavingTwiceOrUnseenChangesNothing() {
        var hold = TitleRowHold()
        let a = UUID()
        hold.set(a, inside: false)
        #expect(!hold.holdsWindow)
        hold.set(a, inside: true)
        hold.set(a, inside: true)
        hold.set(a, inside: false)
        #expect(!hold.holdsWindow)
    }
}

/// Carrying a tab in among the favorites, and a favorite among the others.
@Suite struct TabStripFavoritesTests {
    typealias Item = TabStripLayout.Item

    @Test func leftOfTheRuleIsAmongTheFavorites() {
        let a = UUID(), b = UUID()
        let r = TabStripLayout.layout([.space, .favorite(a), .favorite(b), .rule, .tab(UUID())], width: 900)
        let rule = r.fixed.first { $0.item == .rule }!
        #expect(r.favoritesEdge(reach: 8) == rule.midX)
        #expect(r.favoritesEdge(reach: 8) > r.favorites.last!.maxX)
        #expect(r.favoritesEdge(reach: 8) < r.runX)
    }

    @Test func withNoFavoriteTheStartOfTheTabsIsTheWayIn() {
        let r = TabStripLayout.layout([.space, .tab(UUID()), .tab(UUID())], width: 900)
        #expect(r.favorites.isEmpty)
        #expect(r.favoritesEdge(reach: 8) == r.runX + 8)
    }

    @Test func aFavoritePassesItsNeighbourAtTheMiddle() {
        let a = UUID(), b = UUID(), c = UUID()
        let r = TabStripLayout.layout([.favorite(a), .favorite(b), .favorite(c), .rule, .tab(UUID())], width: 900)
        let slots = r.favorites
        // `a` carried right: it stays first until its middle is past `b`'s, then last past `c`'s.
        #expect(r.favoriteIndex(x: slots[1].midX - 1, moving: a) == 0)
        #expect(r.favoriteIndex(x: slots[1].midX + 1, moving: a) == 1)
        #expect(r.favoriteIndex(x: slots[2].midX + 1, moving: a) == 2)
        // A tab from the run counts every favorite: dropped past the last it is the last.
        #expect(r.favoriteIndex(x: slots[2].maxX, moving: UUID()) == 3)
        #expect(r.favoriteIndex(x: 0, moving: UUID()) == 0)
    }
}

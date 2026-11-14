import Foundation
import NicheCore
import Testing

/// The empty window's home lists the pages last closed in the space (13 Nov 2026).
struct HomeScreenTests {
    private func archived(_ url: String, _ title: String) -> ArchivedItem {
        let tab = SidebarItem.tab(url, title: title, parent: nil)
        return ArchivedItem(archivedAt: Date(timeIntervalSince1970: 0), reason: .manual, sourceSpaceID: nil, wasPinned: false, item: tab)
    }

    @Test func listsTheNewestFour() {
        let items = (1...6).map { archived("https://example.com/\($0)", "Page \($0)") }
        let recents = HomeScreen.recents(items)
        #expect(recents.map(\.title) == ["Page 1", "Page 2", "Page 3", "Page 4"])
        #expect(recents.first?.id == items[0].id)
        #expect(recents.first?.address == "example.com/1")
    }

    @Test func aPageIsListedOnce() {
        let items = [archived("https://www.youtube.com/", "YouTube"), archived("https://youtube.com", "YouTube again"),
                     archived("https://example.com/a", "A")]
        #expect(HomeScreen.recents(items).map(\.title) == ["YouTube", "A"])
    }

    @Test func onlyWebPages() {
        let items = [archived("chrome://settings/", "Settings"), archived("niche://easel/1", "Easel"), archived("https://example.com/", "")]
        let recents = HomeScreen.recents(items)
        #expect(recents.map(\.url) == ["https://example.com/"])
        // A page without a title shows its address.
        #expect(recents.first?.title == "example.com")
    }

    @Test func nothingClosedNothingListed() {
        #expect(HomeScreen.recents([]).isEmpty)
    }
}

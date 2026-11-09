import NicheCore
import Testing

/// The Library's sidebar could not be resized: its lists were cramped with no way to widen them.
/// Its width is the tab sidebar's plus what the user dragged it to, so it follows the sidebar.
struct LibraryWidthTests {
    @Test func untouchedItIsFortyPointsWiderThanTheSidebar() {
        #expect(LibraryWidth.width(sidebar: 280, extra: nil) == 320)
    }

    @Test func aDragKeepsTheDifferenceSoTheLibraryFollowsTheSidebar() {
        let extra = LibraryWidth.extra(forDragged: 460, sidebar: 280)
        #expect(extra == 180)
        #expect(LibraryWidth.width(sidebar: 280, extra: extra) == 460)
        #expect(LibraryWidth.width(sidebar: 320, extra: extra) == 500)
    }

    @Test func itStaysBetweenItsLimits() {
        #expect(LibraryWidth.clamp(100) == LibraryWidth.minimum)
        #expect(LibraryWidth.clamp(2000) == LibraryWidth.maximum)
        #expect(LibraryWidth.width(sidebar: 280, extra: LibraryWidth.extra(forDragged: 2000, sidebar: 280)) == LibraryWidth.maximum)
        #expect(LibraryWidth.width(sidebar: 280, extra: -500) == LibraryWidth.minimum)
    }

    @Test func itIsNeverNarrowerThanTheTabSidebar() {
        #expect(LibraryWidth.clamp(250, sidebar: 360) == 360)
        #expect(LibraryWidth.extra(forDragged: 250, sidebar: 360) == 0)
    }
}

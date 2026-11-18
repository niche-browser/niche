import NicheCore
import Testing

/// A space is named once in the sidebar (13 Nov 2026: beside the traffic lights and again above
/// the tabs), and beside the traffic lights while the toolbar is shown, as in Dia (18 Nov 2026:
/// with two spaces the name was only in the list and the title row stood empty).
struct SidebarHeaderSpaceNameTests {
    typealias T = ToolbarComposition

    @Test func withTheToolbarShownTheTitleRowNamesTheSpace() {
        #expect(T.titleRowNamesSpace(toolbarShown: true, tabsOnTop: false, standaloneWindow: false))
        // However many spaces there are, and whether the bar or the header carries the toggle.
        #expect(T.sidebarHeaderNamesSpace(titleRowNamesSpace: true, headerHasToggle: false, standaloneWindow: false, singleSpaceHeaderHidden: false))
        #expect(T.sidebarHeaderNamesSpace(titleRowNamesSpace: true, headerHasToggle: true, standaloneWindow: false, singleSpaceHeaderHidden: false))
    }

    @Test func thenTheListDoesNotNameItAgain() {
        #expect(!T.listShowsSpaceHeader(titleRowNamesSpace: true, singleSpaceHeaderHidden: false))
        #expect(T.listShowsSpaceHeader(titleRowNamesSpace: false, singleSpaceHeaderHidden: false))
        #expect(!T.listShowsSpaceHeader(titleRowNamesSpace: false, singleSpaceHeaderHidden: true))
    }

    /// With the toolbar hidden the row holds the toggle and the navigation; with the tabs on top
    /// the strip's chip names the space; an incognito or Blank Window has no other space to name.
    @Test func notWithoutTheToolbarOrWithTabsOnTopOrInAWindowOfItsOwn() {
        #expect(!T.titleRowNamesSpace(toolbarShown: false, tabsOnTop: false, standaloneWindow: false))
        #expect(!T.titleRowNamesSpace(toolbarShown: true, tabsOnTop: true, standaloneWindow: false))
        #expect(!T.titleRowNamesSpace(toolbarShown: true, tabsOnTop: false, standaloneWindow: true))
    }

    @Test func withoutASpaceHeaderTheTitleRowNamesASingleSpace() {
        #expect(T.sidebarHeaderNamesSpace(titleRowNamesSpace: false, headerHasToggle: false, standaloneWindow: false, singleSpaceHeaderHidden: true))
        #expect(!T.sidebarHeaderNamesSpace(titleRowNamesSpace: false, headerHasToggle: false, standaloneWindow: false, singleSpaceHeaderHidden: false))
        // The toggle takes that place, and a window of its own has no other space.
        #expect(!T.sidebarHeaderNamesSpace(titleRowNamesSpace: false, headerHasToggle: true, standaloneWindow: false, singleSpaceHeaderHidden: true))
        #expect(!T.sidebarHeaderNamesSpace(titleRowNamesSpace: false, headerHasToggle: false, standaloneWindow: true, singleSpaceHeaderHidden: true))
    }
}

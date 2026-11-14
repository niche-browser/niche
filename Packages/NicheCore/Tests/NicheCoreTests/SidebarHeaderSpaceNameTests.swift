import NicheCore
import Testing

/// A space is named once in the sidebar (13 Nov 2026: beside the traffic lights and again above the tabs).
struct SidebarHeaderSpaceNameTests {
    @Test func theSpaceHeaderNamesTheSpace() {
        #expect(!ToolbarComposition.sidebarHeaderNamesSpace(headerHasToggle: false, standaloneWindow: false, spaceHeaderHidden: false))
    }

    @Test func withoutASpaceHeaderTheTitleRowDoes() {
        #expect(ToolbarComposition.sidebarHeaderNamesSpace(headerHasToggle: false, standaloneWindow: false, spaceHeaderHidden: true))
    }

    /// The toggle takes that place, and an incognito or Blank Window has no other space to name.
    @Test func notBesideTheToggleOrInAWindowOfItsOwn() {
        #expect(!ToolbarComposition.sidebarHeaderNamesSpace(headerHasToggle: true, standaloneWindow: false, spaceHeaderHidden: true))
        #expect(!ToolbarComposition.sidebarHeaderNamesSpace(headerHasToggle: false, standaloneWindow: true, spaceHeaderHidden: true))
    }
}

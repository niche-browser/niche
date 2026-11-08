import NicheCore
import Foundation
import Testing

/// Where a Little Window's page goes when it is sent to a space (GitHub #92).
struct SpaceWindowTests {
    let a = UUID(), b = UUID(), c = UUID()
    let home = UUID(), office = UUID(), work = UUID()

    /// Arc: window A shows the maintainer and was used last, window B shows Office; Office goes to B.
    @Test(.bug("https://github.com/niche-browser/niche/issues/92"))
    func aWindowShowingTheSpaceTakesThePage() {
        #expect(SpaceWindow.window(for: office, windows: [(a, home), (b, office)], lastUsed: a) == b)
        #expect(SpaceWindow.window(for: home, windows: [(a, home), (b, office)], lastUsed: a) == a)
    }

    @Test(.bug("https://github.com/niche-browser/niche/issues/92"))
    func otherwiseTheWindowInUseLastSwitches() {
        #expect(SpaceWindow.window(for: work, windows: [(b, office), (a, home)], lastUsed: a) == a)
        // The window in use can be hidden (the last one closed), so not in the list.
        #expect(SpaceWindow.window(for: work, windows: [], lastUsed: a) == a)
    }

    /// Of several windows on the space, the one in use last, else the frontmost.
    @Test(.bug("https://github.com/niche-browser/niche/issues/92"))
    func severalWindowsOnTheSpace() {
        #expect(SpaceWindow.window(for: office, windows: [(b, office), (c, office), (a, home)], lastUsed: c) == c)
        #expect(SpaceWindow.window(for: office, windows: [(c, office), (b, office), (a, home)], lastUsed: a) == c)
    }
}

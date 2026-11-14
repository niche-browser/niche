import NicheCore
import Testing

/// After a Web Store install Chromium showed "<name> has been added to Chromium" half off the
/// screen's top-left corner, where it stayed (13 Nov 2026, with Niche's window away from the top
/// of the screen). Niche says "Added <name>" itself, so Chromium's bubble is closed.
struct ChromiumAddedBubbleTests {
    let names = ["Bitwarden Password Manager", "uBlock Origin Lite"]

    @Test func theAddedBubbleIsRecognised() {
        #expect(ChromiumAddedBubble.matches(title: "uBlock Origin Lite has been added to Chromium", titled: true,
                                            hasParent: false, extensionNames: names))
    }

    @Test func inAnyLanguage() {
        // Chromium's own words change with the Mac's language; the two names don't.
        #expect(ChromiumAddedBubble.matches(title: "„Bitwarden Password Manager“ wurde zu Chromium hinzugefügt", titled: true,
                                            hasParent: false, extensionNames: names))
        #expect(ChromiumAddedBubble.matches(title: "已将“uBlock Origin Lite”添加到 Chromium", titled: true,
                                            hasParent: false, extensionNames: names))
    }

    @Test func theInstallPromptStays() {
        #expect(!ChromiumAddedBubble.matches(title: "Add \"Bitwarden Password Manager\"?", titled: true,
                                             hasParent: false, extensionNames: names))
        // Also for an extension with the engine's name in its own.
        #expect(!ChromiumAddedBubble.matches(title: "Add \"Chromium Helper\"?", titled: true,
                                             hasParent: false, extensionNames: ["Chromium Helper"]))
    }

    @Test func otherWindowsStay() {
        // A dialog hung from a page (Remove …?), a bubble with no title bar, a window about
        // something else, and an extension Niche doesn't know.
        #expect(!ChromiumAddedBubble.matches(title: "uBlock Origin Lite has been added to Chromium", titled: true,
                                             hasParent: true, extensionNames: names))
        #expect(!ChromiumAddedBubble.matches(title: "uBlock Origin Lite has been added to Chromium", titled: false,
                                             hasParent: false, extensionNames: names))
        #expect(!ChromiumAddedBubble.matches(title: "Chromium isn't your default browser", titled: true,
                                             hasParent: false, extensionNames: names))
        #expect(!ChromiumAddedBubble.matches(title: "Dark Reader has been added to Chromium", titled: true,
                                             hasParent: false, extensionNames: names))
        #expect(!ChromiumAddedBubble.matches(title: "", titled: true, hasParent: false, extensionNames: ["", "A"]))
    }
}

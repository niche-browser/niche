import JavaScriptCore
import NicheCore
import Testing

/// The Chrome Web Store said "Add to Chrome" and asked to "Switch to Chrome" in Niche: Google's page
/// says that to every browser, and a browser that wants its own name there rewrites the page.
struct WebStoreBrandingTests {
    private func relabel(_ text: String) -> String? {
        let js = JSContext()!
        let result = js.evaluateScript("(\(WebStoreBranding.relabel))(\(String(reflecting: text)), 'Niche')")
        return result.flatMap { $0.isNull ? nil : $0.toString() }
    }

    @Test func theInstallButtonsSayNiche() {
        #expect(relabel("Add to Chrome") == "Add to Niche")
        #expect(relabel("  Remove from Chrome ") == "Remove from Niche")
    }

    @Test func everythingElseKeepsItsWords() {
        // The store's own name, other buttons, and a label already rewritten.
        #expect(relabel("Chrome Web Store") == nil)
        #expect(relabel("Install Chrome") == nil)
        #expect(relabel("Add to Niche") == nil)
        #expect(relabel("Add to Chromebook") == nil)
    }

    @Test func itDoesNothingOutsideTheStore() throws {
        // Every page runs it; elsewhere it returns before touching the document (there is none here).
        let js = try #require(JSContext())
        var failure: String?
        js.exceptionHandler = { _, e in failure = e?.toString() }
        js.evaluateScript("var window = this; var location = { hostname: 'example.com' };")
        js.evaluateScript(WebStoreBranding.script(appName: "Niche"))
        #expect(failure == nil)
    }

    @Test func theNameIsQuotedForTheScript() {
        #expect(WebStoreBranding.script(appName: "Ni\"che").contains(#""Ni\"che""#))
    }
}

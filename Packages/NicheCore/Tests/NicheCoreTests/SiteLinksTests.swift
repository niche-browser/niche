import NicheCore
import Testing

/// Visits from the app's buttons showed up as "Direct / None" on the site's analytics.
struct SiteLinksTests {
    @Test func tagsSiteLinksWithTheButton() {
        #expect(SiteLinks.tagged("https://nichebrowser.app/release-notes", from: .whatsNew)
            == "https://nichebrowser.app/release-notes?utm_source=niche-app&utm_campaign=whats-new")
        #expect(SiteLinks.tagged("https://www.nichebrowser.app/help", from: .helpMenu)
            == "https://www.nichebrowser.app/help?utm_source=niche-app&utm_campaign=help-menu")
    }

    @Test func keepsOtherParametersAndTheFragment() {
        #expect(SiteLinks.tagged("https://nichebrowser.app/help/protected-media?x=1#spotify", from: .protectedMedia)
            == "https://nichebrowser.app/help/protected-media?x=1&utm_source=niche-app&utm_campaign=protected-media#spotify")
    }

    @Test func replacesATagAlreadyThere() {
        #expect(SiteLinks.tagged("https://nichebrowser.app/?utm_campaign=old&utm_source=x", from: .helpMenu)
            == "https://nichebrowser.app/?utm_source=niche-app&utm_campaign=help-menu")
    }

    @Test(arguments: ["https://github.com/niche-browser/niche/issues", "http://nichebrowser.app/help",
                      "https://nichebrowser.app.evil.example/", "https://evilnichebrowser.app/", "not a url"])
    func leavesEverythingElseAlone(url: String) {
        #expect(SiteLinks.tagged(url, from: .helpMenu) == url)
    }
}

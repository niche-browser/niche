import NicheCore
import Foundation
import Testing

/// The privacy panel: who a page talked to, what each got, what was stopped (14 Nov 2026).
struct PrivacyLedgerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func request(_ host: String, site: String? = nil, verdict: PrivacyEvent.Verdict = .allowed, listed: Bool = false,
                 sendsSite: Bool = false, sendsPage: Bool = false, bytes: Int64 = 0, after: TimeInterval = 0) -> PrivacyEvent {
        var e = PrivacyEvent(kind: .request, host: host, site: site ?? host.split(separator: ".").suffix(2).joined(separator: "."), at: t0.addingTimeInterval(after))
        e.verdict = verdict
        e.listed = listed
        e.sendsSite = sendsSite
        e.sendsPage = sendsPage
        e.bytesSent = bytes
        e.resource = "script"
        return e
    }

    func cookie(_ kind: PrivacyEvent.Kind, _ host: String, name: String, days: Double = 0) -> PrivacyEvent {
        var e = PrivacyEvent(kind: kind, host: host, site: host.split(separator: ".").suffix(2).joined(separator: "."), at: t0)
        e.detail = name
        e.cookieDays = days
        return e
    }

    func ledger(_ events: [PrivacyEvent]) -> PrivacyLedger {
        var l = PrivacyLedger()
        l.record(PrivacyEvent(kind: .navigation, host: "www.news.test", site: "news.test", at: t0))
        for e in events { l.record(e) }
        return l
    }

    @Test func aCompanysHostsAreOneParty() {
        let l = ledger([request("www.google-analytics.com", verdict: .blockedByList, listed: true),
                        request("stats.g.doubleclick.net", verdict: .blockedByList, listed: true),
                        request("fonts.gstatic.com")])
        #expect(l.parties.count == 1)
        let google = l.parties["google"]
        #expect(google?.name == "Google")
        #expect(google?.categories == [.advertising, .analytics, .hosting])
        #expect(google?.blocked == 2)
        #expect(google?.allowed == 1)
        // Its fonts got through, its trackers didn't.
        #expect(google?.status == .partly)
    }

    /// 14 Nov 2026, first look at the panel: Google's ads and analytics were blocked and only its
    /// fonts loaded, and the panel listed Google under "Can see this visit".
    @Test func aCompanyWhoseTrackersWereBlockedDoesNotSeeTheVisitThroughItsFonts() {
        let l = ledger([request("stats.g.doubleclick.net", verdict: .blockedByList, listed: true),
                        request("fonts.gstatic.com")])
        let google = l.parties["google"]
        #expect(google?.status == .partly)
        #expect(google?.sawYou == false)
        #expect(l.summary.sawYou == 0)
        #expect(l.summary.others == 1)
        #expect(PrivacyWords.status(google!) == "Partly blocked")
        // Its analytics getting through is another matter.
        let seen = ledger([request("stats.g.doubleclick.net", verdict: .blockedByList, listed: true),
                           request("www.googletagmanager.com")])
        #expect(seen.parties["google"]?.sawYou == true)
    }

    /// Third-party cookies are held back: the company asked, and got nothing to recognise you by.
    @Test func cookiesHeldBackAreNotRecognition() {
        var sent = cookie(.cookieSent, "connect.facebook.net", name: "fr")
        sent.verdict = .blockedByList
        var saved = cookie(.cookieSaved, "connect.facebook.net", name: "datr", days: 400)
        saved.verdict = .blockedByList
        let l = ledger([request("connect.facebook.net", sendsSite: true), sent, saved])
        let meta = l.parties["meta"]
        #expect(meta?.cookiesSent.isEmpty == true)
        #expect(meta?.cookiesSaved.isEmpty == true)
        #expect(meta?.cookiesWithheld == ["fr", "datr"])
        #expect(meta?.learned(pageSite: "news.test") == ["That you are on news.test", "Your internet address, which shows roughly where you are"])
        #expect(meta?.withheld == "Niche kept 2 cookies from it, so it can’t tell it is you again.")
        #expect(l.feed.map(\.title).contains("Kept cookies from Meta"))
        #expect(!l.feed.map(\.title).contains("Meta recognised you"))
        #expect(ledger([request("cdn.jsdelivr.net")]).parties["jsdelivr"]?.withheld == nil)
    }

    /// A page asks twice for a script it didn't get (its preload, then the tag itself): one thing
    /// was blocked, and the count says one (14 Nov 2026: the toolbar said 4 for two trackers).
    @Test func theSameAddressBlockedTwiceCountsOnce() {
        var first = request("stats.g.doubleclick.net", verdict: .blockedByList, listed: true)
        first.key = 77
        var other = request("stats.g.doubleclick.net", verdict: .blockedByList, listed: true)
        other.key = 78
        let l = ledger([first, first, other, first])
        #expect(l.parties["google"]?.blocked == 2)
        #expect(l.summary.blockedRequests == 2)
        #expect(l.feed.first?.count == 2)
        // Without an address to tell them apart, each counts.
        let unkeyed = ledger([request("a.doubleclick.net", verdict: .blockedByList, listed: true),
                              request("a.doubleclick.net", verdict: .blockedByList, listed: true)])
        #expect(unkeyed.summary.blockedRequests == 2)
        // A new page starts the count over.
        var again = l
        again.record(PrivacyEvent(kind: .navigation, host: "www.news.test", site: "news.test", at: t0))
        again.record(first)
        #expect(again.summary.blockedRequests == 1)
    }

    /// A third party nobody can name that gets its cookie back knows it is you again: that is
    /// tracking, whatever it calls itself. One the directory knows as a helper (a payment form
    /// keeping its session) is not judged by its cookie.
    @Test func anUnnamedPartyThatRecognisesYouSeesTheVisit() {
        let l = ledger([request("px.adnet.test"), cookie(.cookieSent, "px.adnet.test", name: "uid"),
                        request("js.stripe.com"), cookie(.cookieSent, "js.stripe.com", name: "__stripe_mid"),
                        request("cdn.widgets.test")])
        #expect(l.parties["adnet.test"]?.sawYou == true)
        #expect(PrivacyWords.status(l.parties["adnet.test"]!) == "Sees you")
        #expect(l.parties["stripe"]?.sawYou == false)
        #expect(l.parties["widgets.test"]?.sawYou == false)
        #expect(l.summary.sawYou == 1)
    }

    @Test func anUnknownHostIsListedUnderItsSite() {
        let l = ledger([request("px.adnet.test", verdict: .blockedByList, listed: true), request("cdn.widgets.test")])
        #expect(l.parties["adnet.test"]?.name == "adnet.test")
        #expect(l.parties["adnet.test"]?.known == false)
        // On the list, so it is a tracker though nobody knows whose.
        #expect(l.parties["adnet.test"]?.category == .tracker)
        #expect(l.parties["widgets.test"]?.category == .unknown)
        #expect(l.parties["widgets.test"]?.tracks == false)
    }

    @Test func theSummaryCountsCompaniesNotRequests() {
        let l = ledger([request("connect.facebook.net", verdict: .blockedByList, listed: true),
                        request("connect.facebook.net", verdict: .blockedByList, listed: true),
                        request("static.hotjar.com", sendsSite: true),
                        request("cdn.jsdelivr.net"),
                        request("js.stripe.com")])
        let s = l.summary
        #expect(s.parties == 4)
        #expect(s.blocked == 1)
        #expect(s.sawYou == 1)
        #expect(s.others == 2)
        #expect(s.blockedRequests == 2)
        #expect(s.headline == "1 tracker can see this visit")
    }

    @Test func theHeadlineSaysWhereThingsStand() {
        #expect(ledger([]).summary.headline == "This page hasn’t contacted anyone else")
        #expect(ledger([request("cdn.jsdelivr.net")]).summary.headline == "No trackers on this page")
        #expect(ledger([request("a.doubleclick.net", verdict: .blockedByList, listed: true)]).summary.headline == "Every tracker on this page was blocked")
        let two = ledger([request("static.hotjar.com"), request("cdn.segment.com")])
        #expect(two.summary.headline == "2 trackers can see this visit")
        var cleaned = PrivacyLedger()
        cleaned.record(PrivacyEvent(kind: .navigation, host: "shop.test", site: "shop.test", at: t0))
        cleaned.record(PrivacyEvent(kind: .cleanedAddress, host: "shop.test", site: "shop.test", at: t0))
        #expect(cleaned.summary.headline == "A tracking code was removed from this page’s address")
        #expect(!cleaned.isEmpty)
    }

    @Test func aBlockedPartyLearnedNothing() {
        let l = ledger([request("a.doubleclick.net", verdict: .blockedByList, listed: true)])
        #expect(l.parties["google"]?.learned(pageSite: "news.test") == [])
        #expect(l.parties["google"]?.sawYou == false)
    }

    @Test func whatAnAllowedPartyLearnedIsSaidPlainly() {
        let l = ledger([request("static.hotjar.com", sendsSite: true, sendsPage: true, bytes: 2_300),
                        cookie(.cookieSent, "static.hotjar.com", name: "_hjid"),
                        cookie(.cookieSaved, "static.hotjar.com", name: "_hjSession", days: 0),
                        cookie(.cookieSaved, "static.hotjar.com", name: "_hjid", days: 365)])
        #expect(l.parties["hotjar"]?.learned(pageSite: "news.test") == [
            "Knows it is you again (1 cookie it left went back to it)",
            "The exact page you are on",
            "Your internet address, which shows roughly where you are",
            "Data the page sent it (2 KB)",
            "Left 2 cookies on this Mac, kept for 12 months",
        ])
        // Only the site, when the request didn't say which page.
        let site = ledger([request("cdn.segment.com", sendsSite: true)])
        #expect(site.parties["segment"]?.learned(pageSite: "news.test").first == "That you are on news.test")
        // Nothing but the address, when it said neither.
        let bare = ledger([request("cdn.jsdelivr.net")])
        #expect(bare.parties["jsdelivr"]?.learned(pageSite: "news.test") == ["Your internet address, which shows roughly where you are"])
    }

    @Test func theUsersOwnBlockIsToldApart() {
        let l = ledger([request("cdn.jsdelivr.net", verdict: .blockedByUser)])
        #expect(l.parties["jsdelivr"]?.blockedByUser == true)
        #expect(l.parties["jsdelivr"]?.status == .blocked)
    }

    @Test func theWorstComeFirst() {
        let l = ledger([request("cdn.jsdelivr.net"),
                        request("a.doubleclick.net", verdict: .blockedByList, listed: true),
                        request("cdn.segment.com"),
                        request("static.hotjar.com"),
                        request("js.stripe.com")])
        // Seeing the visit (recording before analytics), then blocked, then what makes the page work.
        #expect(l.sorted.map(\.id) == ["hotjar", "segment", "google", "stripe", "jsdelivr"])
    }

    @Test func aNewPageStartsOver() {
        var l = ledger([request("static.hotjar.com")])
        l.record(PrivacyEvent(kind: .navigation, host: "shop.test", site: "shop.test", at: t0.addingTimeInterval(5)))
        #expect(l.parties.isEmpty)
        #expect(l.feed.isEmpty)
        #expect(l.pageSite == "shop.test")
        #expect(l.started == t0.addingTimeInterval(5))
        l.record(request("cdn.segment.com"))
        l.reset(pageSite: "other.test", at: t0.addingTimeInterval(9))
        #expect(l.isEmpty)
        #expect(l.pageSite == "other.test")
    }

    @Test func theFeedIsOneLinePerThingNotALog() {
        let l = ledger([request("a.doubleclick.net", verdict: .blockedByList, listed: true),
                        request("static.hotjar.com", after: 1),
                        request("b.doubleclick.net", verdict: .blockedByList, listed: true, after: 2),
                        request("cdn.jsdelivr.net", after: 3)])
        #expect(l.feed.map(\.title) == ["Hotjar saw this visit", "Blocked Google", "jsDelivr loaded"])
        #expect(l.feed.map(\.count) == [1, 2, 1])
        #expect(l.feed.map(\.tone) == [.saw, .blocked, .neutral])
        #expect(l.feed[1].detail == "Advertising")
        #expect(l.feed[1].at == t0.addingTimeInterval(2))
    }

    @Test func cookiesAreSaidOnce() {
        let l = ledger([request("static.hotjar.com"),
                        cookie(.cookieSent, "static.hotjar.com", name: "_hjid"),
                        cookie(.cookieSent, "static.hotjar.com", name: "_hjid"),
                        cookie(.cookieSent, "static.hotjar.com", name: "_hjTLD"),
                        cookie(.cookieSaved, "static.hotjar.com", name: "_hjid", days: 30),
                        cookie(.cookieSaved, "static.hotjar.com", name: "_hjid", days: 400)])
        #expect(l.parties["hotjar"]?.cookiesSent == ["_hjid", "_hjTLD"])
        #expect(l.parties["hotjar"]?.cookiesSaved == ["_hjid": 400])
        let titles = l.feed.map(\.title)
        #expect(titles.filter { $0 == "Hotjar recognised you" }.count == 1)
        #expect(titles.filter { $0 == "Hotjar left a cookie" }.count == 1)
        #expect(l.feed.first { $0.title == "Hotjar recognised you" }?.count == 1)
    }

    @Test func aProbeMakesItsScriptAFingerprinter() {
        var l = ledger([request("cdn.widgets.test")])
        l.record(PrivacyEvent(kind: .probe(.webgl), host: "cdn.widgets.test", site: "widgets.test", at: t0))
        l.record(PrivacyEvent(kind: .probe(.webgl), host: "cdn.widgets.test", site: "widgets.test", at: t0))
        l.record(PrivacyEvent(kind: .probe(.canvas), host: "cdn.widgets.test", site: "widgets.test", at: t0))
        let p = l.parties["widgets.test"]
        #expect(p?.categories == [.fingerprinting])
        #expect(p?.sawYou == true)
        #expect(p?.learned(pageSite: "news.test").prefix(2) == ["Read how your Mac draws text and shapes", "Read your graphics chip"])
        #expect(l.feed.map(\.title).contains("widgets.test read your graphics chip"))
        #expect(l.feed.filter { $0.title.contains("graphics chip") }.count == 1)
        // The site's own script can do it too: it is named and counted under Fingerprinting, as
        // "This site" (the site sees its own visitors; it is not somebody else watching).
        l.record(PrivacyEvent(kind: .probe(.audio), host: "www.news.test", site: "news.test", at: t0))
        #expect(l.parties["news.test"]?.probes == [.audio])
        #expect(l.parties["news.test"]?.listing == .other)
        #expect(l.summary.fingerprinters == 2)
    }

    @Test func theFeedKeepsTheNewestLines() {
        var l = ledger([])
        for i in 0..<(PrivacyLedger.feedLimit + 5) { l.record(request("cdn.site\(i).test", after: Double(i))) }
        #expect(l.feed.count == PrivacyLedger.feedLimit)
        #expect(l.feed.first?.title == "site5.test loaded")
    }

    @Test(arguments: [(0.0, "until you quit Niche"), (0.4, "for less than a day"), (1, "for a day"), (6, "for 6 days"),
                      (21, "for 3 weeks"), (395, "for 13 months"), (800, "for 2 years")])
    func durationsReadLikeSpeech(days: Double, words: String) {
        #expect(PrivacyWords.duration(days: days) == words)
    }

    @Test func theToolbarButtonSaysWhatItCounts() {
        #expect(PrivacyWords.badge(0) == "")
        #expect(PrivacyWords.badge(7) == "7")
        #expect(PrivacyWords.badge(140) == "99+")
        #expect(PrivacyWords.shieldLabel(blocked: 0, sawYou: nil) == "Privacy: nothing blocked on this page")
        #expect(PrivacyWords.shieldLabel(blocked: 12, sawYou: 2) == "Privacy: 12 blocked on this page, 2 trackers can see this visit")
        #expect(PrivacyWords.shieldLabel(blocked: 12, sawYou: 0) == "Privacy: 12 blocked on this page")
        #expect(PrivacyWords.count(1, "cookie") == "1 cookie")
    }
}

struct PrivacyWordsTests {
    @Test func aChoiceIsSaidBack() {
        #expect(PrivacyWords.said(.standard, name: "Hotjar") == nil)
        #expect(PrivacyWords.said(.blockedHere, name: "Hotjar") == "You blocked Hotjar on this site.")
        #expect(PrivacyWords.said(.blockedEverywhere, name: "Hotjar") == "You blocked Hotjar on every site.")
        #expect(PrivacyWords.said(.allowedHere, name: "Hotjar") == "You allowed Hotjar on this site.")
        #expect(PrivacyWords.said(.allowedEverywhere, name: "Hotjar") == "You allowed Hotjar on every site.")
    }

    @Test func blockingACompanySaysWhatElseStops() {
        #expect(PrivacyWords.blockCaveat(party: "google", name: "Google", tracks: true)
                == "Blocking Google also stops its sign-in, videos and fonts on pages that use them.")
        #expect(PrivacyWords.blockCaveat(party: "stripe", name: "Stripe", tracks: false) == "Blocking Stripe also stops its payments on pages that use them.")
        // A pure tracker: nothing else goes.
        #expect(PrivacyWords.blockCaveat(party: "hotjar", name: "Hotjar", tracks: true) == nil)
        // A site nobody knows: a tracker can go, anything else the page may need.
        #expect(PrivacyWords.blockCaveat(party: "adnet.test", name: "adnet.test", tracks: true) == nil)
        #expect(PrivacyWords.blockCaveat(party: "widgets.test", name: "widgets.test", tracks: false) == "The page may not work without it.")
    }

    @Test func aRowSaysWhereItsPartyStands() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var p = PrivacyLedger.Party(id: "hotjar", name: "Hotjar", known: true, lastSeen: t0)
        p.categories = [.sessionRecording]
        p.blocked = 2
        #expect(PrivacyWords.status(p) == "Blocked")
        p.allowed = 1
        #expect(PrivacyWords.status(p) == "Partly blocked")
        p.blocked = 0
        p.allowedCategories = [.sessionRecording]
        #expect(PrivacyWords.status(p) == "Sees you")
        var cdn = PrivacyLedger.Party(id: "jsdelivr", name: "jsDelivr", known: true, lastSeen: t0)
        cdn.categories = [.hosting]
        cdn.allowed = 3
        #expect(PrivacyWords.status(cdn) == "Allowed")
        cdn.blocked = 1
        #expect(PrivacyWords.status(cdn) == "Partly blocked")
    }
}

struct TrackerDirectoryTests {
    let directory = TrackerDirectory.standard

    @Test func aHostBelongsToTheCompanyOfItsMostSpecificDomain() {
        #expect(directory.match(host: "stats.g.doubleclick.net")?.company.name == "Google")
        #expect(directory.match(host: "stats.g.doubleclick.net")?.category == .advertising)
        #expect(directory.match(host: "fonts.googleapis.com")?.category == .hosting)
        #expect(directory.match(host: "maps.googleapis.com")?.category == .media)
        #expect(directory.match(host: "accounts.google.com")?.category == .security)
        // What pages embed from google.com itself is sign-in and reCAPTCHA, not an ad.
        #expect(directory.match(host: "www.google.com")?.category == .security)
        #expect(directory.match(host: "adservice.google.com")?.category == .advertising)
        #expect(directory.match(host: "ip-api.com")?.company.id != directory.match(host: "ipapi.co")?.company.id)
        #expect(directory.match(host: "WWW.Google.com")?.category == .security)
        #expect(directory.match(host: "challenges.cloudflare.com")?.category == .security)
        #expect(directory.match(host: "cdnjs.cloudflare.com")?.category == .hosting)
        #expect(directory.match(host: "www.clarity.ms")?.category == .sessionRecording)
    }

    @Test func whatItDoesNotKnowItDoesNotGuess() {
        #expect(directory.match(host: "example.org") == nil)
        #expect(directory.match(host: "notdoubleclick.net") == nil)
        #expect(directory.match(host: "net") == nil)
        #expect(directory.match(host: "") == nil)
    }

    @Test func aCompanyHasItsDomainsAndWhatTheyAreFor() {
        #expect(directory.domains(of: "hotjar") == ["hotjar.com", "hotjar.io"])
        #expect(directory.categories(of: "google") == [.advertising, .analytics, .security, .media, .hosting])
        #expect(directory.domains(of: "nobody").isEmpty)
        #expect(directory.company("meta")?.name == "Meta")
        #expect(directory.companyCount > 150)
        #expect(directory.domainCount > 400)
    }

    /// A domain in two rows would give a host two owners; one category per domain.
    @Test func noDomainIsListedTwice() {
        var seen: [String: Int] = [:]
        for id in ["google", "meta", "microsoft", "amazon", "adobe", "oracle", "salesforce", "cloudflare", "akamai", "fastly", "shopify",
                   "automattic", "vercel", "nielsen", "yahoo", "yandex", "apple", "tiktok", "x", "snap"] {
            for d in directory.domains(of: id) { seen[d, default: 0] += 1 }
        }
        #expect(seen.values.allSatisfy { $0 == 1 })
        // Every listed domain leads back to the company that lists it.
        for id in ["google", "hotjar", "stripe", "criteo"] {
            for d in directory.domains(of: id) { #expect(directory.match(host: d)?.company.id == id) }
        }
    }

    @Test func everyCategoryHasWordsForPeople() {
        for c in TrackerCategory.allCases {
            #expect(!c.title.isEmpty)
            #expect(c.explanation.hasSuffix("."))
            #expect(!c.symbol.isEmpty)
        }
        #expect(TrackerCategory.sessionRecording < .advertising)
        #expect(TrackerCategory.advertising < .hosting)
        #expect(TrackerCategory.analytics.tracks)
        #expect(!TrackerCategory.hosting.tracks)
        #expect(!TrackerCategory.unknown.tracks)
    }
}

struct PrivacyRulesTests {
    @Test func nothingChosenLeavesItToTheList() {
        let rules = PrivacyRules()
        #expect(rules.choice(for: "google", on: "news.test") == .standard)
        #expect(rules.isEmpty)
        #expect(rules.compiled() == PrivacyRules.Compiled())
    }

    @Test func aChoiceForThisSiteStaysOnThisSite() {
        var rules = PrivacyRules()
        rules.set(.blockedHere, for: "jsdelivr", on: "news.test")
        #expect(rules.choice(for: "jsdelivr", on: "news.test") == .blockedHere)
        #expect(rules.choice(for: "jsdelivr", on: "shop.test") == .standard)
        rules.set(.allowedHere, for: "jsdelivr", on: "news.test")
        #expect(rules.choice(for: "jsdelivr", on: "news.test") == .allowedHere)
        #expect(rules.blockedOn.isEmpty)
        rules.set(.standard, for: "jsdelivr", on: "news.test")
        #expect(rules.isEmpty)
    }

    @Test func aChoiceForEverySiteReplacesTheOthers() {
        var rules = PrivacyRules()
        rules.set(.allowedHere, for: "hotjar", on: "news.test")
        rules.set(.blockedHere, for: "hotjar", on: "shop.test")
        rules.set(.blockedEverywhere, for: "hotjar", on: "news.test")
        #expect(rules.choice(for: "hotjar", on: "news.test") == .blockedEverywhere)
        #expect(rules.choice(for: "hotjar", on: "shop.test") == .blockedEverywhere)
        #expect(rules.allowedOn.isEmpty && rules.blockedOn.isEmpty)
        rules.set(.allowedEverywhere, for: "hotjar", on: "x.test")
        #expect(rules.blocked.isEmpty)
        #expect(rules.choice(for: "hotjar", on: "any.test") == .allowedEverywhere)
    }

    @Test func aSitesOwnChoiceWinsOverTheOneForEverySite() {
        var rules = PrivacyRules()
        rules.set(.blockedEverywhere, for: "google", on: "news.test")
        rules.set(.allowedHere, for: "google", on: "maps.test")
        #expect(rules.choice(for: "google", on: "maps.test") == .allowedHere)
        #expect(rules.choice(for: "google", on: "news.test") == .blockedEverywhere)
        // Back to standard on that site: the choice for every site shows through again.
        rules.set(.standard, for: "google", on: "maps.test")
        #expect(rules.choice(for: "google", on: "maps.test") == .blockedEverywhere)
        // Standard where the everywhere choice is in force clears that.
        rules.set(.standard, for: "google", on: "news.test")
        #expect(rules.isEmpty)
    }

    @Test func protectionCanBeOffForASite() {
        var rules = PrivacyRules()
        rules.setOff(true, on: "bank.test")
        #expect(rules.isOff(on: "bank.test"))
        #expect(!rules.isOff(on: "news.test"))
        #expect(rules.compiled().offSites == ["bank.test"])
        rules.setOff(false, on: "bank.test")
        #expect(rules.isEmpty)
    }

    @Test func theEngineGetsDomains() {
        var rules = PrivacyRules()
        rules.set(.blockedEverywhere, for: "hotjar", on: "news.test")
        rules.set(.blockedEverywhere, for: "adnet.test", on: "news.test")
        rules.set(.allowedHere, for: "stripe", on: "shop.test")
        rules.set(.blockedHere, for: "widgets.test", on: "news.test")
        let c = rules.compiled()
        #expect(c.blocked == ["adnet.test", "hotjar.com", "hotjar.io"])
        #expect(c.allowedOn == ["shop.test": ["stripe.com", "stripe.network", "stripecdn.com"]])
        #expect(c.blockedOn == ["news.test": ["widgets.test"]])
        #expect(c.allowed.isEmpty)
    }

    @Test func theFileRoundTripsAndAnOlderOneLoads() throws {
        var rules = PrivacyRules()
        rules.set(.blockedEverywhere, for: "hotjar", on: "news.test")
        rules.set(.allowedHere, for: "stripe", on: "shop.test")
        rules.setOff(true, on: "bank.test")
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode(PrivacyRules.self, from: data) == rules)
        #expect(try JSONDecoder().decode(PrivacyRules.self, from: Data("{}".utf8)) == PrivacyRules())
        #expect(try JSONDecoder().decode(PrivacyRules.self, from: Data(#"{"blocked":["hotjar"]}"#.utf8)).choice(for: "hotjar", on: "a.test") == .blockedEverywhere)
    }

    @Test func everyChoiceHasItsMenuTitle() {
        #expect(PrivacyRules.Choice.allCases.map(\.title) == ["Let Niche Decide", "Block on This Site", "Block Everywhere",
                                                              "Allow on This Site", "Allow Everywhere"])
    }
}

struct PrivacySettingsTests {
    /// Privacy is why Niche exists: the protections are on until someone turns them off.
    @Test func theProtectionsAreOnByDefault() {
        let settings = AppSettings()
        #expect(settings.blockAdsAndTrackers)
        #expect(settings.blockThirdPartyCookies)
        #expect(settings.removeTrackingParameters)
        #expect(settings.sendGlobalPrivacyControl)
        #expect(settings.noticeFingerprinting)
    }

    @Test func aSettingsFileFromBeforeThemTurnsThemOn() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"blockAdsAndTrackers": false}"#.utf8))
        #expect(!old.blockAdsAndTrackers)
        #expect(old.blockThirdPartyCookies && old.removeTrackingParameters && old.sendGlobalPrivacyControl && old.noticeFingerprinting)
    }

    @Test func turningOneOffIsKept() throws {
        var settings = AppSettings()
        settings.blockThirdPartyCookies = false
        settings.sendGlobalPrivacyControl = false
        settings.noticeFingerprinting = false
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(!saved.blockThirdPartyCookies)
        #expect(!saved.sendGlobalPrivacyControl)
        #expect(!saved.noticeFingerprinting)
        #expect(saved.removeTrackingParameters)
    }
}

struct PrivacySiteTests {
    /// The same cases as Tests/Engine/ContentBlockerTests.cc: the panel's rules are kept by site.
    @Test(arguments: [("a.b.example.co.uk", "example.co.uk"), ("127.0.0.1", "127.0.0.1"), ("www.news.test", "news.test"),
                      ("someone.github.io", "someone.github.io"), ("www.someone.github.io", "someone.github.io"), ("github.io", "github.io"),
                      ("shop.myshopify.com", "shop.myshopify.com"),
                      ("news.test", "news.test"), ("localhost", "localhost"), ("WWW.Example.COM.", "example.com"),
                      ("shop.example.com.au", "example.com.au"), ("a.b.c.example.de", "example.de")])
    func aHostsSite(host: String, site: String) {
        #expect(PrivacySite.site(ofHost: host) == site)
    }

    @Test func onlyWebPagesHaveASite() {
        #expect(PrivacySite.site(ofURL: "https://www.news.test/a/b?c=1") == "news.test")
        #expect(PrivacySite.site(ofURL: "http://127.0.0.1:8765/") == "127.0.0.1")
        #expect(PrivacySite.site(ofURL: "niche://settings") == nil)
        #expect(PrivacySite.site(ofURL: "file:///tmp/a.html") == nil)
        #expect(PrivacySite.site(ofURL: "") == nil)
    }
}

struct PrivacyStatsTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func countingBeginsWithTheFirstBlock() {
        var stats = PrivacyStats()
        let day = Date(timeIntervalSince1970: 1_794_614_400)   // 14 Nov 2026
        #expect(stats.line(calendar: utc) == nil)
        stats.add(0, at: day)
        #expect(stats.since == nil)
        stats.add(1, at: day)
        #expect(stats.line(calendar: utc) == "1 tracker blocked since 14 Nov 2026")
        stats.add(12_479, at: day.addingTimeInterval(86_400 * 40))
        #expect(stats.since == day)
        #expect(stats.line(calendar: utc) == "12,480 trackers blocked since 14 Nov 2026")
    }

    /// The panel's week: a count per day, the last two weeks kept.
    @Test func eachDayHasItsOwnCount() {
        var stats = PrivacyStats()
        let day = Date(timeIntervalSince1970: 1_794_614_400)   // 14 Nov 2026
        stats.add(3, at: day, calendar: utc)
        stats.add(2, at: day.addingTimeInterval(3_600), calendar: utc)
        stats.add(4, at: day.addingTimeInterval(86_400 * 2), calendar: utc)
        let now = day.addingTimeInterval(86_400 * 2 + 60)
        #expect(stats.recent(4, now: now, calendar: utc).map(\.blocked) == [0, 5, 0, 4])
        #expect(stats.today(now: now, calendar: utc) == 4)
        #expect(stats.total == "9")
        for i in 3..<30 { stats.add(1, at: day.addingTimeInterval(86_400 * Double(i)), calendar: utc) }
        #expect(stats.days.count == PrivacyStats.daysKept)
        #expect(stats.days["2026-11-14"] == nil)
        #expect(stats.blocked == 36)
    }

    @Test func theFileRoundTrips() throws {
        var stats = PrivacyStats()
        stats.add(7, at: Date(timeIntervalSince1970: 1_794_614_400))
        #expect(try JSONDecoder().decode(PrivacyStats.self, from: JSONEncoder().encode(stats)) == stats)
        #expect(try JSONDecoder().decode(PrivacyStats.self, from: Data("{}".utf8)) == PrivacyStats())
    }
}

/// A tab's pages: the panel shows the page on screen, whenever it is opened and however the
/// page was reached (17 Nov 2026: it used to ask for a reload, and Back showed the wrong page).
struct PrivacyPagesTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func navigation(_ site: String) -> PrivacyEvent { PrivacyEvent(kind: .navigation, host: "www." + site, site: site, at: t0) }

    func request(_ host: String, blocked: Bool = false, key: UInt64 = 0) -> PrivacyEvent {
        var e = PrivacyEvent(kind: .request, host: host, site: host.split(separator: ".").suffix(2).joined(separator: "."), at: t0)
        e.verdict = blocked ? .blockedByList : .allowed
        e.listed = blocked
        e.key = key
        return e
    }

    @Test func goingBackShowsThatPagesLedger() {
        var pages = PrivacyPages()
        pages.record(navigation("news.test"), pageKey: 1, pageSite: "news.test")
        pages.record(request("ads.adnet.test", blocked: true, key: 9), pageKey: 1, pageSite: "news.test")
        pages.record(navigation("shop.test"), pageKey: 2, pageSite: "shop.test")
        pages.record(request("cdn.widgets.test"), pageKey: 2, pageSite: "shop.test")
        #expect(pages.ledger(pageKey: 2, site: "shop.test").parties.keys.sorted() == ["widgets.test"])
        // Back: the browser shows the first page again without asking for anything.
        #expect(pages.ledger(pageKey: 1, site: "news.test").parties.keys.sorted() == ["adnet.test"])
        // What it does now that it is back is added to its own ledger.
        pages.record(request("px.tracker.test", blocked: true, key: 10), pageKey: 1, pageSite: "news.test")
        #expect(pages.ledger(pageKey: 1, site: "news.test").parties.count == 2)
        #expect(pages.ledger(pageKey: 2, site: "shop.test").parties.count == 1)
    }

    @Test func twoPagesOfOneSiteAreToldApart() {
        var pages = PrivacyPages()
        pages.record(navigation("news.test"), pageKey: 1, pageSite: "news.test")
        pages.record(request("ads.adnet.test", blocked: true, key: 9), pageKey: 1, pageSite: "news.test")
        pages.record(navigation("news.test"), pageKey: 2, pageSite: "news.test")
        #expect(pages.ledger(pageKey: 2, site: "news.test").isEmpty)
        #expect(pages.ledger(pageKey: 1, site: "news.test").summary.blocked == 1)
    }

    @Test func aReloadStartsThePageOver() {
        var pages = PrivacyPages()
        pages.record(navigation("news.test"), pageKey: 1, pageSite: "news.test")
        pages.record(request("ads.adnet.test", blocked: true, key: 9), pageKey: 1, pageSite: "news.test")
        pages.record(navigation("news.test"), pageKey: 1, pageSite: "news.test")
        #expect(pages.pages.count == 1)
        #expect(pages.ledger(pageKey: 1, site: "news.test").isEmpty)
    }

    /// A single-page app changes its address without a load; a redirect answers under another one.
    @Test func aPageKeepsItsLedgerWhenItsAddressChanges() {
        var pages = PrivacyPages()
        pages.record(navigation("video.test"), pageKey: 1, pageSite: "video.test")
        pages.record(request("ads.adnet.test", blocked: true, key: 9), pageKey: 1, pageSite: "video.test")
        pages.record(request("px.tracker.test", blocked: true, key: 10), pageKey: 5, pageSite: "video.test")
        #expect(pages.pages.count == 1)
        #expect(pages.ledger(pageKey: 5, site: "video.test").summary.blocked == 2)
        #expect(pages.ledger(pageKey: 77, site: "video.test").summary.blocked == 2)
        // A short link: asked for on one site, answered on another.
        pages.record(navigation("short.test"), pageKey: 20, pageSite: "short.test")
        pages.record(request("ads.adnet.test", blocked: true, key: 9), pageKey: 21, pageSite: "news.test")
        #expect(pages.pages.count == 2)
        #expect(pages.ledger(pageKey: 21, site: "news.test").pageSite == "news.test")
        #expect(pages.ledger(pageKey: 21, site: "news.test").summary.blocked == 1)
    }

    @Test func aBlockedRequestIsCountedOnceForTheTotal() {
        var pages = PrivacyPages()
        pages.record(navigation("news.test"), pageKey: 1, pageSite: "news.test")
        #expect(pages.record(request("ads.adnet.test", blocked: true, key: 9), pageKey: 1, pageSite: "news.test") == 1)
        #expect(pages.record(request("ads.adnet.test", blocked: true, key: 9), pageKey: 1, pageSite: "news.test") == 0)
        #expect(pages.record(request("cdn.widgets.test"), pageKey: 1, pageSite: "news.test") == 0)
    }

    @Test func onlyTheLastFewPagesAreKept() {
        var pages = PrivacyPages()
        for i in 1...20 { pages.record(navigation("site\(i).test"), pageKey: UInt64(i), pageSite: "site\(i).test") }
        #expect(pages.pages.count == PrivacyPages.limit)
        #expect(pages.ledger(pageKey: 1, site: "site1.test").isEmpty)
    }

    /// A page nobody announced (restored before Niche listened) still gets a ledger.
    @Test func aPageNobodyAnnouncedGetsALedger() {
        var pages = PrivacyPages()
        pages.record(request("ads.adnet.test", blocked: true, key: 9), pageKey: 4, pageSite: "news.test")
        #expect(pages.ledger(pageKey: 4, site: "news.test").summary.blocked == 1)
    }
}

struct PrivacySummaryTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theSummaryCountsWhatThePanelLists() {
        var l = PrivacyLedger(pageSite: "news.test", started: t0)
        var blocked = PrivacyEvent(kind: .request, host: "www.google-analytics.com", site: "google-analytics.com", at: t0)
        blocked.verdict = .blockedByList
        blocked.listed = true
        blocked.key = 1
        l.record(blocked)
        l.record(PrivacyEvent(kind: .request, host: "cdn.widgets.test", site: "widgets.test", at: t0))
        var kept = PrivacyEvent(kind: .cookieSent, host: "cdn.widgets.test", site: "widgets.test", at: t0)
        kept.verdict = .blockedByList
        kept.detail = "id"
        l.record(kept)
        l.record(PrivacyEvent(kind: .probe(.canvas), host: "cdn.widgets.test", site: "widgets.test", at: t0))
        let s = l.summary
        #expect(s.blockedRequests == 1)
        #expect(s.allowedRequests == 1)
        #expect(s.cookiesWithheld == 1)
        #expect(s.cookiesPassed == 0)
        #expect(s.fingerprinters == 1)
        #expect(s.kinds.map(\.count).reduce(0, +) == s.parties)
        #expect(s.kinds.first?.category == .fingerprinting)
    }

    /// A page that asks for ever doesn't grow the ledger for ever.
    @Test func blockedAddressesAreRememberedUpToALimit() {
        var l = PrivacyLedger(pageSite: "news.test", started: t0)
        for i in 1...(PrivacyLedger.blockedKeyLimit + 50) {
            var e = PrivacyEvent(kind: .request, host: "ads.adnet.test", site: "adnet.test", at: t0)
            e.verdict = .blockedByList
            e.key = UInt64(i)
            l.record(e)
        }
        #expect(l.summary.blockedRequests == PrivacyLedger.blockedKeyLimit + 50)
        var again = PrivacyEvent(kind: .request, host: "ads.adnet.test", site: "adnet.test", at: t0)
        again.verdict = .blockedByList
        again.key = 1
        l.record(again)
        #expect(l.summary.blockedRequests == PrivacyLedger.blockedKeyLimit + 50)
    }
}

/// The top of the panel: where the page stands and what each protection did, in plain words.
struct PrivacyReportTests {
    typealias Summary = PrivacyLedger.Summary

    @Test func theHeadlineSaysWhereThePageStands() {
        #expect(PrivacyReport.standing(Summary(), siteOff: false)
                == .init(title: "This page keeps to itself", detail: "It hasn’t contacted any other company.", tone: .good))
        #expect(PrivacyReport.standing(Summary(parties: 2, others: 2), siteOff: false).title == "No trackers here")
        let protected = PrivacyReport.standing(Summary(parties: 6, blocked: 5, others: 1, blockedRequests: 12, cookiesWithheld: 1, cleanedAddress: true), siteOff: false)
        #expect(protected == .init(title: "You’re protected", detail: "5 companies blocked, 1 cookie kept back, address cleaned.", tone: .good))
        let seen = PrivacyReport.standing(Summary(parties: 3, blocked: 1, sawYou: 2), siteOff: false)
        #expect(seen == .init(title: "2 trackers can see this visit", detail: "1 company blocked. Open a tracker below to block it.", tone: .bad))
        #expect(PrivacyReport.standing(Summary(parties: 1, sawYou: 1), siteOff: false).detail == "Open one below to block it.")
        #expect(PrivacyReport.standing(Summary(parties: 1, sawYou: 1), siteOff: true)
                == .init(title: "Protection is off here", detail: "1 tracker can see this visit.", tone: .off))
        #expect(PrivacyReport.standing(Summary(), siteOff: true).detail == "Nothing is blocked on this site.")
    }

    @Test func eachProtectionSaysWhatItDid() {
        let busy = Summary(parties: 4, blocked: 3, sawYou: 1, blockedRequests: 7, cookiesWithheld: 2, fingerprinters: 1, cleanedAddress: true)
        let rows = PrivacyReport.rows(busy, protections: PrivacyProtections(), siteOff: false, secure: true)
        #expect(rows.map(\.kind) == PrivacyReport.Row.Kind.allCases)
        #expect(rows.map(\.value) == ["7 requests stopped", "2 kept back", "Removed", "Sent", "1 company tried", "Encrypted"])
        #expect(rows.map(\.tone) == [PrivacyReport.Tone.good, .good, .good, .good, .bad, .good])
        let quiet = PrivacyReport.rows(Summary(), protections: PrivacyProtections(), siteOff: false, secure: false)
        #expect(quiet.map(\.value) == ["None found", "None asked for", "None found", "Sent", "None noticed", "Not encrypted"])
        #expect(quiet.map(\.tone) == [PrivacyReport.Tone.quiet, .quiet, .quiet, .good, .quiet, .bad])
    }

    /// A protection that is switched off says so, and never claims a result.
    @Test func aProtectionThatIsOffSaysOff() {
        let busy = Summary(parties: 4, blocked: 3, blockedRequests: 7, cookiesWithheld: 2, cleanedAddress: true)
        let none = PrivacyProtections(blocksTrackers: false, withholdsCookies: false, cleansAddresses: false, sendsSignal: false, noticesFingerprinting: false)
        #expect(PrivacyReport.rows(busy, protections: none, siteOff: false, secure: true).map(\.value) == ["Off", "Off", "Off", "Off", "Off", "Encrypted"])
        // The site's own switch stops blocking and cookie holding there; the rest goes on.
        #expect(PrivacyReport.rows(busy, protections: PrivacyProtections(), siteOff: true, secure: true).map(\.value)
                == ["Off for this site", "Off for this site", "Removed", "Sent", "None noticed", "Encrypted"])
    }

    @Test func protectionsFollowTheSettings() {
        var settings = AppSettings()
        settings.blockThirdPartyCookies = false
        settings.noticeFingerprinting = false
        let p = PrivacyProtections(settings)
        #expect(p == PrivacyProtections(withholdsCookies: false, noticesFingerprinting: false))
    }

    @Test(arguments: [(2.0, "now"), (12.0, "12 s"), (240.0, "4 min"), (7300.0, "2 h")])
    func feedTimesReadShort(seconds: Double, words: String) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PrivacyReport.ago(now.addingTimeInterval(-seconds), now: now) == words)
    }
}

/// A window too narrow for the panel grows to hold it, rather than opening a panel nobody sees.
struct PrivacyPanelFitTests {
    @Test func aPageKeepsAPhonesWidthBesideThePanel() {
        #expect(PrivacyPanelFit.pageMinimum(panes: 1, paneMinimum: 240, gap: 8, sideBySide: true) == 320)
        #expect(PrivacyPanelFit.pageMinimum(panes: 2, paneMinimum: 240, gap: 8, sideBySide: true) == 488)
        #expect(PrivacyPanelFit.pageMinimum(panes: 2, paneMinimum: 240, gap: 8, sideBySide: false) == 320)
        // The 1010 pt window that showed no panel: 770 of content, a 360 pt panel.
        #expect(PrivacyPanelFit.fits(content: 770, panel: 360, gap: 8, pages: 320))
        #expect(!PrivacyPanelFit.fits(content: 560, panel: 360, gap: 8, pages: 320))
        #expect(PrivacyPanelFit.shortfall(content: 560, panel: 360, gap: 8, pages: 320) == 128)
    }

    @Test func aNarrowWindowGrowsWithinTheScreen() {
        // Room to the right.
        #expect(PrivacyPanelFit.grown(x: 100, width: 800, by: 128, visibleMinX: 0, visibleMaxX: 1440) == (100, 928))
        // Against the right edge: it moves left.
        #expect(PrivacyPanelFit.grown(x: 640, width: 800, by: 128, visibleMinX: 0, visibleMaxX: 1440) == (512, 928))
        // A screen that can't hold it: the whole width, no more.
        #expect(PrivacyPanelFit.grown(x: 0, width: 800, by: 400, visibleMinX: 0, visibleMaxX: 1000) == (0, 1000))
        #expect(PrivacyPanelFit.grown(x: 100, width: 800, by: 0, visibleMinX: 0, visibleMaxX: 1440) == (100, 800))
    }
}

/// youtube.com is Google's: its own company on its own site is not a tracker that "sees you"
/// (17 Nov 2026: the panel said "1 tracker can see this visit" on YouTube, meaning Google).
struct PrivacySiteOwnerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theSitesOwnCompanyIsNotATrackerThere() {
        var l = PrivacyLedger(pageSite: "youtube.com", started: t0)
        var analytics = PrivacyEvent(kind: .request, host: "www.google-analytics.com", site: "google-analytics.com", at: t0)
        analytics.listed = true
        l.record(analytics)
        l.record(PrivacyEvent(kind: .probe(.webgl), host: "www.gstatic.com", site: "gstatic.com", at: t0))
        let google = l.parties["google"]
        #expect(google?.ownsSite == true)
        #expect(google?.sawYou == false)
        #expect(l.summary.sawYou == 0)
        #expect(l.summary.others == 1)
        #expect(google.map(PrivacyWords.status) == "This site")
        #expect(PrivacyReport.standing(l.summary, siteOff: false).title == "No trackers here")
        // The same company on somebody else's site is one.
        var other = PrivacyLedger(pageSite: "news.test", started: t0)
        other.record(analytics)
        #expect(other.parties["google"]?.ownsSite == false)
        #expect(other.parties["google"]?.sawYou == true)
    }
}

/// The filter lists say why they blocked something, and a site's own ads are the site's.
struct PrivacyShieldsLedgerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func blocked(_ host: String, site: String, group: ShieldsGroup?, key: UInt64, byUser: Bool = false) -> PrivacyEvent {
        var e = PrivacyEvent(kind: .request, host: host, site: site, at: t0)
        e.verdict = byUser ? .blockedByUser : .blockedByList
        e.listed = !byUser
        e.group = group
        e.key = key
        return e
    }

    @Test func aBlockedCompanySaysWhichListsItIsOn() {
        var l = PrivacyLedger(pageSite: "news.test", started: t0)
        l.record(blocked("ads.adnet.test", site: "adnet.test", group: .ads, key: 1))
        l.record(blocked("px.adnet.test", site: "adnet.test", group: .trackers, key: 2))
        #expect(l.parties["adnet.test"]?.blockedWhy == "Blocked because it is on the ad lists and the tracker lists.")
        l.record(blocked("cdn.widgets.test", site: "widgets.test", group: nil, key: 3, byUser: true))
        #expect(l.parties["widgets.test"]?.blockedWhy == "You blocked it.")
        l.record(blocked("x.other.test", site: "other.test", group: nil, key: 4))
        #expect(l.parties["other.test"]?.blockedWhy == "Blocked by the filter lists.")
        l.record(PrivacyEvent(kind: .request, host: "fonts.test", site: "fonts.test", at: t0))
        #expect(l.parties["fonts.test"]?.blockedWhy == nil)
        #expect(PrivacyWords.list(["a", "b", "c"]) == "a, b and c")
    }

    /// An ad a site serves from its own address is blocked and counted, and is the site's own.
    @Test func aSitesOwnBlockedRequestsBelongToTheSite() {
        var l = PrivacyLedger(pageSite: "news.test", started: t0)
        l.record(blocked("www.news.test", site: "news.test", group: .ads, key: 1))
        let own = l.parties["news.test"]
        #expect(own?.ownsSite == true && own?.sawYou == false)
        #expect(l.summary.blockedRequests == 1)
        // Listed with the rest as "This site", not as a company that was kept out.
        #expect(l.summary.blocked == 0 && l.summary.sawYou == 0 && l.summary.others == 1)
        #expect(own.map(PrivacyWords.status) == "This site" && own?.listing == .other)
        #expect(l.feed.map(\.title) == ["Blocked ads or trackers from this site"])
    }
}

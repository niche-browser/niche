import Foundation
import NicheCore
import Testing

/// uBlock Origin Lite's four filtering modes, for every site and for one.
struct FilteringModeTests {
    @Test func nicheStartsWithOptimalAsUBlockOriginLiteDoes() {
        #expect(AppSettings().filteringMode == .optimal)
        #expect(FilteringMode.standard == .optimal)
    }

    @Test func eachModeAddsToTheOneBefore() {
        #expect(!FilteringMode.none.blocksRequests)
        #expect(FilteringMode.basic.blocksRequests && !FilteringMode.basic.appliesSiteRules)
        #expect(FilteringMode.optimal.appliesSiteRules && !FilteringMode.optimal.hidesGenerically)
        #expect(FilteringMode.complete.hidesGenerically && FilteringMode.complete.appliesSiteRules && FilteringMode.complete.blocksRequests)
        #expect(FilteringMode.allCases == FilteringMode.allCases.sorted())
    }

    @Test func theModeForEverySiteIsNeverOff() {
        #expect(!FilteringMode.forEverySite.contains(.none))
        #expect(FilteringMode(stored: 0) == .none)
        #expect(FilteringMode(stored: 9) == .standard)
        #expect(FilteringMode(stored: nil) == .standard)
    }

    @Test func aSiteCanHaveAModeOfItsOwn() {
        var rules = PrivacyRules()
        #expect(rules.mode(on: "video.example", standard: .optimal) == .optimal)
        #expect(rules.ownMode(on: "video.example") == nil)
        rules.setMode(.complete, on: "video.example", standard: .optimal)
        #expect(rules.mode(on: "video.example", standard: .optimal) == .complete)
        #expect(rules.mode(on: "other.example", standard: .optimal) == .optimal)
        rules.setMode(.none, on: "video.example", standard: .optimal)
        #expect(rules.isOff(on: "video.example"))
        #expect(rules.mode(on: "video.example", standard: .optimal) == FilteringMode.none)
        #expect(rules.siteModes.isEmpty)
    }

    /// Picking the mode every site has is going back to the setting: the site follows it when it
    /// changes later, and nothing is left to reset.
    @Test func theStandardModeIsNoModeOfItsOwn() {
        var rules = PrivacyRules()
        rules.setMode(.basic, on: "shop.example", standard: .optimal)
        rules.setMode(.optimal, on: "shop.example", standard: .optimal)
        #expect(rules.isEmpty)
        #expect(rules.mode(on: "shop.example", standard: .complete) == .complete)
    }

    @Test func protectionOffAndOnStillWork() {
        var rules = PrivacyRules()
        rules.setMode(.basic, on: "shop.example", standard: .optimal)
        rules.setOff(true, on: "shop.example")
        #expect(rules.ownMode(on: "shop.example") == FilteringMode.none)
        rules.setOff(false, on: "shop.example")
        #expect(rules.ownMode(on: "shop.example") == nil)
    }

    @Test func theEngineIsToldEverySitesOwnMode() {
        var rules = PrivacyRules()
        rules.setMode(.none, on: "off.example", standard: .optimal)
        rules.setMode(.basic, on: "basic.example", standard: .optimal)
        let compiled = rules.compiled()
        #expect(compiled.siteModes == ["off.example": 0, "basic.example": 1])
        #expect(compiled.offSites == ["off.example"])
    }

    @Test func aSitesModeSurvivesASave() throws {
        var rules = PrivacyRules()
        rules.setMode(.complete, on: "news.example", standard: .optimal)
        let back = try JSONDecoder().decode(PrivacyRules.self, from: JSONEncoder().encode(rules))
        #expect(back == rules)
        // A file from before the modes has none.
        let old = try JSONDecoder().decode(PrivacyRules.self, from: Data(#"{"offSites":["a.example"]}"#.utf8))
        #expect(old.ownMode(on: "a.example") == FilteringMode.none && old.siteModes.isEmpty)
    }

    @Test func aLevelSetsItsMode() {
        var settings = AppSettings()
        PrivacyLevel.relaxed.apply(to: &settings)
        #expect(settings.filteringMode == .basic)
        PrivacyLevel.strict.apply(to: &settings)
        #expect(settings.filteringMode == .complete)
        PrivacyLevel.balanced.apply(to: &settings)
        #expect(settings.filteringMode == .optimal && PrivacyLevel.level(of: settings) == .balanced)
        settings.filteringMode = .complete
        #expect(PrivacyLevel.level(of: settings) == nil)
    }

    /// Settings saved before the modes keep their level: Strict stays Strict.
    @Test func settingsFromBeforeTheModesKeepTheirLevel() throws {
        for level in PrivacyLevel.allCases {
            var settings = AppSettings()
            level.apply(to: &settings)
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
            json["filteringMode"] = nil
            let back = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
            #expect(PrivacyLevel.level(of: back) == level)
        }
        // And a mode that is not one for every site is not kept.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any])
        json["filteringMode"] = 0
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json)).filteringMode == .optimal)
    }
}

/// The optional lists Settings ▸ Privacy "More lists" offers.
struct ShieldsCatalogTests {
    private let catalog = ShieldsCatalog(lists: [
        .init(id: "adguard-ads", title: "AdGuard – Ads", group: "ads"),
        .init(id: "annoyances-social", title: "EasyList – Social Widgets", group: "annoyances"),
        .init(id: "block-lan", title: "Block Outsider Intrusion into LAN", group: "trackers"),
    ])

    @Test func onlySwitchedOnListsAreWanted() {
        #expect(catalog.wanted([]).isEmpty)
        #expect(catalog.wanted(["block-lan", "adguard-ads", "gone"]).map(\.id) == ["adguard-ads", "block-lan"])
    }

    @Test func settingsShowThemByWhatTheyAreFor() {
        #expect(catalog.sections.map(\.group) == [.ads, .trackers, .annoyances])
    }

    @Test func aCatalogueWithNewFieldsOrAnUnknownGroupStillReads() throws {
        let json = #"{"built":"2026-11-18T00:00:00Z","lists":[{"id":"new","title":"New","group":"something-new","bytes":12,"extra":true},{"id":"bare"}]}"#
        let read = try JSONDecoder().decode(ShieldsCatalog.self, from: Data(json.utf8))
        #expect(read.lists.map(\.id) == ["new", "bare"])
        #expect(read.lists[0].shieldsGroup == .ads && read.lists[1].title == "bare")
    }

    @Test func nicheLooksForNewerListsEverySixHours() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!ShieldsUpdate.isDue(lastSuccess: now.addingTimeInterval(-5 * 3600), lastAttempt: nil, now: now))
        #expect(ShieldsUpdate.isDue(lastSuccess: now.addingTimeInterval(-6 * 3600), lastAttempt: nil, now: now))
        #expect(ShieldsUpdate.extraPack("adguard-ads") == "shields-x-adguard-ads.pack")
    }
}

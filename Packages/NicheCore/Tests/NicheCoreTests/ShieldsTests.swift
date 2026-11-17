import CryptoKit
import Foundation
import NicheCore
import Testing

/// Shields: the pack Niche downloads, which lists it uses, and the privacy levels over them.
struct ShieldsPackTests {
    /// A pack as scripts/shields-pack.mjs writes one: raw-deflated JSON.
    static func file(format: Int = 1, lists: [[String: Any]], resources: [String: Any] = [:]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: ["format": format, "built": "2026-11-17T08:00:00.000Z", "lists": lists, "resources": resources])
        return try (json as NSData).compressed(using: .zlib) as Data
    }

    static let lists: [[String: Any]] = [
        ["id": "unbreak", "group": "core", "title": "Unbreak", "licence": "GPL-3.0", "homepage": "https://example.org", "trusted": true, "text": "@@||ok.example^"],
        ["id": "ads", "group": "ads", "title": "Ads", "trusted": false, "text": "||ads.example^"],
        ["id": "privacy", "group": "trackers", "title": "Privacy", "trusted": true, "text": "||tracker.example^"],
        ["id": "cookies", "group": "cookies", "title": "Cookies", "text": "##.cookie-banner"],
        ["id": "future", "group": "something-new", "title": "A kind this build doesn't know", "text": "||x.example^"],
        ["id": "DEU-0", "group": "regional", "title": "EasyList Germany", "languages": ["de"], "text": "||werbung.example^"],
    ]

    @Test func aPackIsReadWithWhatEachListIsFor() throws {
        let pack = try ShieldsPack.read(Self.file(lists: Self.lists, resources: ["scriptlets": [["name": "noop.js"]], "redirects": []]))
        #expect(pack.lists.map(\.id) == ["unbreak", "ads", "privacy", "cookies", "DEU-0"])   // the unknown kind is skipped
        #expect(pack.lists[0].group == .core && pack.lists[0].trusted && pack.lists[0].licence == "GPL-3.0")
        #expect(pack.lists[1].text == Data("||ads.example^".utf8) && !pack.lists[1].trusted)
        #expect(pack.lists[4].languages == ["de"])
        #expect(pack.built == Date(timeIntervalSince1970: 1_794_902_400))
        #expect(String(data: pack.scriptlets, encoding: .utf8) == #"[{"name":"noop.js"}]"#)
        #expect(pack.redirects.isEmpty)
    }

    @Test func somethingThatIsNotAPackIsRefused() throws {
        #expect(throws: ShieldsPack.Failure.notAPack) { try ShieldsPack.read(Data("hello".utf8)) }
        #expect(throws: ShieldsPack.Failure.notAPack) { try ShieldsPack.read((Data(#"{"lists": 3}"#.utf8) as NSData).compressed(using: .zlib) as Data) }
        // A format newer than this build reads: it keeps the pack it has.
        #expect(throws: ShieldsPack.Failure.newerFormat(2)) { try ShieldsPack.read(Self.file(format: 2, lists: [])) }
    }

    @Test func onlyAPackSignedWithTheKeyIsTrusted() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let file = try Self.file(lists: Self.lists)
        let signature = try key.signature(for: file).base64EncodedString()
        #expect(ShieldsPack.isSigned(file, signature: signature + "\n", key: publicKey))
        #expect(!ShieldsPack.isSigned(file + Data([0]), signature: signature, key: publicKey))
        #expect(!ShieldsPack.isSigned(file, signature: signature, key: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
        #expect(!ShieldsPack.isSigned(file, signature: "not base64", key: publicKey))
        #expect(!ShieldsPack.isSigned(file, signature: signature))   // not the real key
        #expect(Data(base64Encoded: ShieldsPack.publicKey)?.count == 32)
    }

    @Test func theSwitchesChooseTheLists() throws {
        let pack = try ShieldsPack.read(Self.file(lists: Self.lists))
        #expect(pack.lists(for: [.ads, .trackers]).map(\.id) == ["unbreak", "ads", "privacy"])
        #expect(pack.lists(for: [.cookies]).map(\.id) == ["unbreak", "cookies"])
        // Nothing switched on: nothing, the fixes included.
        #expect(pack.lists(for: []).isEmpty)
        #expect(pack.lists(for: [.malware]).isEmpty)   // a group the pack has no list for
    }

    @Test func aGroupHasANumberTheEngineHandsBack() {
        for group in ShieldsGroup.allCases {
            #expect(ShieldsGroup(number: group.number) == group)
            #expect(!group.title.isEmpty && !group.detail.isEmpty && !group.listsWords.isEmpty)
        }
        #expect(ShieldsGroup(number: 99) == nil && ShieldsGroup(number: -1) == nil)
        #expect(Set(ShieldsGroup.allCases.map(\.symbol)).count == ShieldsGroup.allCases.count)
    }

    @Test func regionalListsFollowTheMacsLanguages() throws {
        let index = try JSONDecoder().decode(ShieldsRegionalIndex.self, from: Data(#"""
        {"built": "2026-11-17", "lists": [{"id": "DEU-0", "title": "EasyList Germany", "languages": ["de", "rm"], "bytes": 5},
                                           {"id": "FRA-0", "title": "AdGuard Français", "languages": ["fr"]}]}
        """#.utf8))
        #expect(index.wanted(languages: ["en-US", "de-CH"]).map(\.id) == ["DEU-0"])
        #expect(index.wanted(languages: ["fr_CA", "DE"]).map(\.id) == ["DEU-0", "FRA-0"])
        #expect(index.wanted(languages: ["en-GB"]).isEmpty)
        #expect(ShieldsUpdate.regionalPack("DEU-0") == "shields-DEU-0.pack")
    }

    @Test func itLooksForNewerPacksOnceADay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ShieldsUpdate.isDue(lastSuccess: nil, lastAttempt: nil, now: now))
        #expect(!ShieldsUpdate.isDue(lastSuccess: now.addingTimeInterval(-3600), lastAttempt: nil, now: now))
        #expect(ShieldsUpdate.isDue(lastSuccess: now.addingTimeInterval(-25 * 3600), lastAttempt: nil, now: now))
        // A look that failed is tried again after an hour, not at once.
        #expect(!ShieldsUpdate.isDue(lastSuccess: nil, lastAttempt: now.addingTimeInterval(-600), now: now))
        #expect(ShieldsUpdate.isDue(lastSuccess: nil, lastAttempt: now.addingTimeInterval(-3700), now: now))
    }
}

struct PrivacyLevelTests {
    @Test func nicheStartsBalanced() {
        #expect(PrivacyLevel.recommended == .balanced)
        #expect(PrivacyLevel.level(of: AppSettings()) == .balanced)
        #expect(AppSettings().shieldsGroups == [.ads, .trackers, .cookies, .malware, .regional])
    }

    @Test func aLevelSetsItsSwitches() {
        var settings = AppSettings()
        PrivacyLevel.relaxed.apply(to: &settings)
        #expect(settings.blockTrackers && settings.blockMaliciousSites)
        #expect(!settings.blockAds && !settings.blockCookieNotices && !settings.blockThirdPartyCookies && !settings.blockAnnoyances && !settings.httpsOnly)
        #expect(settings.shieldsGroups == [.trackers, .malware, .regional])
        #expect(PrivacyLevel.level(of: settings) == .relaxed)
        PrivacyLevel.strict.apply(to: &settings)
        #expect(settings.blockAds && settings.blockCookieNotices && settings.blockThirdPartyCookies && settings.blockAnnoyances && settings.httpsOnly)
        #expect(PrivacyLevel.level(of: settings) == .strict)
        // The switches a level doesn't own stay as they were.
        settings.sendGlobalPrivacyControl = false
        PrivacyLevel.balanced.apply(to: &settings)
        #expect(!settings.sendGlobalPrivacyControl && PrivacyLevel.level(of: settings) == .balanced)
    }

    @Test func aSwitchChangedByHandLeavesNoLevel() {
        var settings = AppSettings()
        settings.blockCookieNotices = false
        #expect(PrivacyLevel.level(of: settings) == nil)
        settings.blockCookieNotices = true
        settings.blockAnnoyances = true   // Strict's, without its secure connections
        #expect(PrivacyLevel.level(of: settings) == nil)
    }

    @Test func everythingOffAsksForNoLists() {
        var settings = AppSettings()
        settings.blockAds = false
        settings.blockTrackers = false
        settings.blockCookieNotices = false
        settings.blockMaliciousSites = false
        #expect(settings.shieldsGroups.isEmpty)   // the regional lists go with the rest
        settings.blockAds = true
        settings.useRegionalLists = false
        #expect(settings.shieldsGroups == [.ads])
    }

    /// One switch used to cover ads and trackers; a settings file from then keeps its choice for both.
    @Test func theOldSwitchStandsForAdsAndTrackers() throws {
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"blockAdsAndTrackers": false, "blockCookieBanners": false}"#.utf8))
        #expect(!off.blockAds && !off.blockTrackers)
        // "Block cookie banners" was off for everyone by default: the new switch starts on.
        #expect(off.blockCookieNotices)
        let on = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(on.blockAds && on.blockTrackers && on.blockMaliciousSites && on.useRegionalLists && !on.blockAnnoyances)
        var mixed = AppSettings()
        mixed.blockAds = false
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(mixed))
        #expect(!saved.blockAds && saved.blockTrackers)
    }

    @Test func eachLevelSaysWhatItDoes() {
        for level in PrivacyLevel.allCases {
            #expect(!level.title.isEmpty && !level.tagline.isEmpty && level.points.count == 3)
        }
        #expect(Set(PrivacyLevel.allCases.map(\.symbol)).count == 3)
    }
}

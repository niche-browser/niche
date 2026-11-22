import Foundation
import NicheCore
import Testing

/// Each browser profile has its own Settings ▸ Privacy and its own privacy panel choices. On
/// 22 Nov 2026 there was one set for every profile: what one space's profile was set to showed,
/// and applied, in every other.
struct ProfilePrivacyTests {
    private let hobbies = PrivacyProfile.key(profileID: UUID(uuidString: "B0000000-0000-0000-0000-000000000001"))
    private let work = PrivacyProfile.key(profileID: UUID(uuidString: "B0000000-0000-0000-0000-000000000002"))

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// The engine knows a page's profile by its Chromium folder.
    @Test func aProfileGoesByItsFolder() {
        let id = UUID()
        #expect(PrivacyProfile.key(profileID: id) == BrowserProfile(id: id, name: "x").directoryName)
        #expect(PrivacyProfile.key(profileID: nil) == "Default")
    }

    @Test(.bug("https://github.com/niche-browser/niche/issues/18"))
    func aChangeStaysInItsProfile() {
        var s = AppSettings()
        s.adoptPrivacy(profiles: [hobbies, work])
        var h = s.privacy(forProfile: hobbies)
        h.blockTrackers = false
        h.filteringMode = .basic
        s.setPrivacy(h, forProfile: hobbies)
        #expect(s.privacy(forProfile: hobbies).blockTrackers == false)
        #expect(s.privacy(forProfile: hobbies).filteringMode == .basic)
        #expect(s.privacy.blockTrackers == true)
        #expect(s.privacy.filteringMode == .standard)
        #expect(s.privacy(forProfile: work) == PrivacySettings())

        // And the Default profile's own change goes nowhere else.
        s.blockAds = false
        #expect(s.privacy(forProfile: hobbies).blockAds == true)
        #expect(s.privacy(forProfile: work).blockAds == true)
    }

    /// A settings file from before: every profile starts with the one set there was, so an update
    /// changes nothing until a profile is changed.
    @Test(.bug("https://github.com/niche-browser/niche/issues/18"))
    func anUpdateGivesEveryProfileTheSettingsThereWere() throws {
        var s = try decode(AppSettings.self, #"{"blockAds": false, "filteringMode": 3, "httpsOnly": true}"#)
        #expect(s.profilePrivacy.isEmpty)
        s.adoptPrivacy(profiles: [hobbies])
        #expect(s.privacy(forProfile: hobbies) == s.privacy)
        #expect(s.privacy(forProfile: hobbies).blockAds == false)
        #expect(s.privacy(forProfile: hobbies).filteringMode == .complete)
    }

    /// A profile made later starts as the Default profile is then, and is its own from there.
    @Test func aNewProfileStartsAsDefaultIs() {
        var s = AppSettings()
        s.blockAnnoyances = true
        s.adoptPrivacy(profiles: [hobbies])
        s.blockAnnoyances = false
        s.adoptPrivacy(profiles: [hobbies, work])
        #expect(s.privacy(forProfile: hobbies).blockAnnoyances == true)
        #expect(s.privacy(forProfile: work).blockAnnoyances == false)
    }

    @Test func aDeletedProfilesSettingsGo() {
        var s = AppSettings()
        s.adoptPrivacy(profiles: [hobbies, work])
        s.adoptPrivacy(profiles: [work])
        #expect(s.profilePrivacy.keys.sorted() == [work])
    }

    @Test func settingsKeepEachProfilesOwn() throws {
        var s = AppSettings()
        s.adoptPrivacy(profiles: [hobbies])
        var h = s.privacy(forProfile: hobbies)
        h.blockCookieNotices = false
        h.extraShieldsLists = ["adguard-ads"]
        s.setPrivacy(h, forProfile: hobbies)
        let read = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(read.privacy(forProfile: hobbies) == h)
        #expect(read.privacy == s.privacy)
    }

    /// The level is a profile's: Strict in one, Relaxed in another.
    @Test func eachProfileHasItsLevel() {
        var s = AppSettings()
        s.adoptPrivacy(profiles: [hobbies])
        var h = s.privacy(forProfile: hobbies)
        PrivacyLevel.strict.apply(to: &h)
        s.setPrivacy(h, forProfile: hobbies)
        PrivacyLevel.relaxed.apply(to: &s)
        #expect(PrivacyLevel.level(of: s.privacy(forProfile: hobbies)) == .strict)
        #expect(PrivacyLevel.level(of: s) == .relaxed)
        #expect(s.privacy(forProfile: hobbies).shieldsGroups.contains(.annoyances))
        #expect(!s.shieldsGroups.contains(.ads))
    }

    /// Profiles that ask for the same lists share an engine.
    @Test func theSameListsAreOneEngine() {
        var a = PrivacySettings(), b = PrivacySettings()
        b.blockAnnoyances = false
        a.filteringMode = .complete   // the mode isn't a list
        #expect(a.shieldsLists == b.shieldsLists)
        b.blockAds = false
        #expect(a.shieldsLists != b.shieldsLists)
        var off = PrivacySettings()
        off.blockAds = false; off.blockTrackers = false; off.blockCookieNotices = false; off.blockMaliciousSites = false
        #expect(off.shieldsLists.isOff)
    }

    // MARK: The privacy panel's choices

    @Test(.bug("https://github.com/niche-browser/niche/issues/18"))
    func aSiteChoiceStaysInItsProfile() {
        var book = PrivacyRuleBook()
        book.adopt(profiles: [hobbies])
        book["Default"].setOff(true, on: "news.example")
        book[hobbies].set(.blockedEverywhere, for: "google", on: "news.example")
        #expect(book["Default"].offSites == ["news.example"])
        #expect(book[hobbies].offSites.isEmpty)
        #expect(book["Default"].choice(for: "google", on: "news.example") == .standard)
        #expect(book[hobbies].choice(for: "google", on: "news.example") == .blockedEverywhere)
    }

    /// privacy.json from before: its choices are every profile's after the update, once.
    @Test func anOldRulesFileIsEveryProfiles() throws {
        var book = try decode(PrivacyRuleBook.self, #"{"offSites": ["news.example"], "siteModes": {"shop.example": 1}}"#)
        #expect(book.sharedByEveryProfile)
        book.adopt(profiles: [hobbies])
        #expect(book[hobbies].offSites == ["news.example"])
        #expect(book[hobbies].siteModes == ["shop.example": 1])
        // Written back, it is no longer shared: a profile made later starts with none.
        var read = try JSONDecoder().decode(PrivacyRuleBook.self, from: JSONEncoder().encode(book))
        #expect(!read.sharedByEveryProfile)
        read.adopt(profiles: [hobbies, work])
        #expect(read[work] == PrivacyRules())
        #expect(read[hobbies].offSites == ["news.example"])
        #expect(read["Default"].offSites == ["news.example"])
    }

    /// The Default profile's choices stay where older versions read them.
    @Test func defaultsChoicesStayAtTheTop() throws {
        var book = PrivacyRuleBook()
        book["Default"].setOff(true, on: "news.example")
        book[hobbies].setOff(true, on: "shop.example")
        let old = try JSONDecoder().decode(PrivacyRules.self, from: JSONEncoder().encode(book))
        #expect(old.offSites == ["news.example"])
    }

    @Test func aDeletedProfilesChoicesGo() {
        var book = PrivacyRuleBook()
        book.adopt(profiles: [hobbies])
        book[hobbies].setOff(true, on: "shop.example")
        book.adopt(profiles: [])
        #expect(book[hobbies] == PrivacyRules())
        #expect(book.profiles.isEmpty)
    }
}

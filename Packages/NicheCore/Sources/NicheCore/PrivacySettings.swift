import Foundation

/// One browser profile's Settings ▸ Privacy: what Shields blocks and how much, and the switches
/// beside it. Each profile has its own (22 Nov 2026: there was one set for every profile, so what
/// one space's profile was set to showed, and applied, in every other). The Default profile's
/// stay at the top of settings.json, where every version has read them; every other profile's
/// are under `profilePrivacy`, by its folder name, with the same keys.
///
/// Secure DNS is not here: Chromium keeps it for the whole app (Local State).
public struct PrivacySettings: Codable, Equatable, Hashable, Sendable {
    /// "Trackers" (`ShieldsGroup.trackers`). The key keeps the name it had when one switch
    /// covered ads and trackers; code reads it as `blockTrackers`.
    public var blockAdsAndTrackers: Bool = true
    /// "Ads" (`ShieldsGroup.ads`).
    public var blockAds: Bool = true
    /// "Cookie notices" (`ShieldsGroup.cookies`).
    public var blockCookieNotices: Bool = true
    /// "Pop-ups and nags" (`ShieldsGroup.annoyances`): on at the Strict level only.
    public var blockAnnoyances: Bool = false
    /// "Dangerous sites" (`ShieldsGroup.malware`).
    public var blockMaliciousSites: Bool = true
    /// "Lists for your languages" (`ShieldsGroup.regional`).
    public var useRegionalLists: Bool = true
    /// "Filtering": how much Shields does on every site (`FilteringMode`); a site can have its
    /// own in the privacy panel. Never `none`.
    public var filteringMode: FilteringMode = .standard
    /// "More lists": the optional lists switched on, by id (`ShieldsCatalog`).
    public var extraShieldsLists: Set<String> = []
    /// "Always use secure connections": Chrome's HTTPS-Only Mode.
    public var httpsOnly: Bool = false
    /// "Block third-party cookies".
    public var blockThirdPartyCookies: Bool = true
    /// "Remove tracking codes from links".
    public var removeTrackingParameters: Bool = true
    /// "Tell websites not to sell or share my data": Global Privacy Control.
    public var sendGlobalPrivacyControl: Bool = true
    /// "Notice fingerprinting" (`PrivacyProbeScript`).
    public var noticeFingerprinting: Bool = true

    public init() {}

    /// Tolerant: a key that isn't there keeps its default, and a profile's entry written by a
    /// later version with keys this one doesn't know still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockAdsAndTrackers = try c.decodeIfPresent(Bool.self, forKey: .blockAdsAndTrackers) ?? true
        blockAds = try c.decodeIfPresent(Bool.self, forKey: .blockAds) ?? blockAdsAndTrackers
        blockCookieNotices = try c.decodeIfPresent(Bool.self, forKey: .blockCookieNotices) ?? true
        blockAnnoyances = try c.decodeIfPresent(Bool.self, forKey: .blockAnnoyances) ?? false
        blockMaliciousSites = try c.decodeIfPresent(Bool.self, forKey: .blockMaliciousSites) ?? true
        useRegionalLists = try c.decodeIfPresent(Bool.self, forKey: .useRegionalLists) ?? true
        extraShieldsLists = try c.decodeIfPresent(Set<String>.self, forKey: .extraShieldsLists) ?? []
        httpsOnly = try c.decodeIfPresent(Bool.self, forKey: .httpsOnly) ?? false
        blockThirdPartyCookies = try c.decodeIfPresent(Bool.self, forKey: .blockThirdPartyCookies) ?? true
        removeTrackingParameters = try c.decodeIfPresent(Bool.self, forKey: .removeTrackingParameters) ?? true
        sendGlobalPrivacyControl = try c.decodeIfPresent(Bool.self, forKey: .sendGlobalPrivacyControl) ?? true
        noticeFingerprinting = try c.decodeIfPresent(Bool.self, forKey: .noticeFingerprinting) ?? true
        if let mode = try c.decodeIfPresent(Int.self, forKey: .filteringMode).flatMap(FilteringMode.init(rawValue:)), mode != .none {
            filteringMode = mode
        } else {
            filteringMode = PrivacyLevel.allCases.first { $0.sets(self, ignoringMode: true) }?.filteringMode ?? .standard
        }
    }

    /// "Trackers". Stored under the name of the one switch that used to cover ads too.
    public var blockTrackers: Bool {
        get { blockAdsAndTrackers }
        set { blockAdsAndTrackers = newValue }
    }

    /// The groups of filter lists the switches ask for.
    public var shieldsGroups: Set<ShieldsGroup> {
        var groups: Set<ShieldsGroup> = []
        if blockAds { groups.insert(.ads) }
        if blockTrackers { groups.insert(.trackers) }
        if blockCookieNotices { groups.insert(.cookies) }
        if blockAnnoyances { groups.insert(.annoyances) }
        if blockMaliciousSites { groups.insert(.malware) }
        if !groups.isEmpty, useRegionalLists { groups.insert(.regional) }
        return groups
    }

    /// The lists a profile's engine is built from: profiles that ask for the same ones share it.
    public var shieldsLists: ShieldsLists { ShieldsLists(groups: shieldsGroups, extras: extraShieldsLists) }
}

/// The filter lists one engine is built from: the groups switched on and the optional lists.
public struct ShieldsLists: Hashable, Sendable {
    public var groups: Set<ShieldsGroup>
    public var extras: Set<String>

    public init(groups: Set<ShieldsGroup>, extras: Set<String> = []) {
        self.groups = groups
        self.extras = extras
    }

    /// Nothing switched on: no engine.
    public var isOff: Bool { groups.isEmpty }
}

/// The name a browser profile's privacy goes by: its Chromium folder ("Default", "Profile
/// <UUID>"), which is also what the engine knows a page's profile by. Incognito windows share
/// one context with no folder and follow the Default profile.
public enum PrivacyProfile {
    public static let defaultKey = "Default"

    public static func key(profileID: UUID?) -> String {
        profileID.map { "Profile \($0.uuidString)" } ?? defaultKey
    }
}

public extension AppSettings {
    /// The Default profile's privacy: the keys at the top of settings.json.
    var privacy: PrivacySettings {
        get {
            var p = PrivacySettings()
            p.blockAdsAndTrackers = blockAdsAndTrackers
            p.blockAds = blockAds
            p.blockCookieNotices = blockCookieNotices
            p.blockAnnoyances = blockAnnoyances
            p.blockMaliciousSites = blockMaliciousSites
            p.useRegionalLists = useRegionalLists
            p.filteringMode = filteringMode
            p.extraShieldsLists = extraShieldsLists
            p.httpsOnly = httpsOnly
            p.blockThirdPartyCookies = blockThirdPartyCookies
            p.removeTrackingParameters = removeTrackingParameters
            p.sendGlobalPrivacyControl = sendGlobalPrivacyControl
            p.noticeFingerprinting = noticeFingerprinting
            return p
        }
        set {
            blockAdsAndTrackers = newValue.blockAdsAndTrackers
            blockAds = newValue.blockAds
            blockCookieNotices = newValue.blockCookieNotices
            blockAnnoyances = newValue.blockAnnoyances
            blockMaliciousSites = newValue.blockMaliciousSites
            useRegionalLists = newValue.useRegionalLists
            filteringMode = newValue.filteringMode
            extraShieldsLists = newValue.extraShieldsLists
            httpsOnly = newValue.httpsOnly
            blockThirdPartyCookies = newValue.blockThirdPartyCookies
            removeTrackingParameters = newValue.removeTrackingParameters
            sendGlobalPrivacyControl = newValue.sendGlobalPrivacyControl
            noticeFingerprinting = newValue.noticeFingerprinting
        }
    }

    /// A profile's privacy, by `PrivacyProfile.key`. One that has none of its own yet (made since
    /// `adoptPrivacy` last ran) reads as the Default profile's.
    func privacy(forProfile key: String) -> PrivacySettings {
        key == PrivacyProfile.defaultKey ? privacy : profilePrivacy[key] ?? privacy
    }

    mutating func setPrivacy(_ settings: PrivacySettings, forProfile key: String) {
        if key == PrivacyProfile.defaultKey { privacy = settings } else { profilePrivacy[key] = settings }
    }

    /// Gives each profile that has no privacy of its own a copy of the Default profile's (every
    /// profile, the first time a version with per-profile privacy opens a settings file, so nothing
    /// changes on update; and a profile made since), and forgets the ones of profiles that are gone.
    /// `profiles`: the keys of the profiles there are besides Default.
    mutating func adoptPrivacy(profiles: Set<String>) {
        for key in profiles where key != PrivacyProfile.defaultKey && profilePrivacy[key] == nil {
            profilePrivacy[key] = privacy
        }
        for key in profilePrivacy.keys where !profiles.contains(key) { profilePrivacy[key] = nil }
    }
}

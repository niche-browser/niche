import Foundation

/// How much Niche does for the user's privacy, as one choice: what onboarding asks, and the
/// picker at the top of Settings ▸ Privacy. A level is a preset over the switches below it;
/// changing a switch by hand leaves no level selected ("Custom").
public enum PrivacyLevel: String, CaseIterable, Sendable {
    case relaxed, balanced, strict

    /// The one Niche starts with.
    public static let recommended = PrivacyLevel.balanced

    public var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .balanced: "Balanced"
        case .strict: "Strict"
        }
    }

    /// One line under the title.
    public var tagline: String {
        switch self {
        case .relaxed: "Stops trackers and leaves pages as their sites made them."
        case .balanced: "Private by default, and the web still works."
        case .strict: "Everything Niche can do. A few sites may need a hand."
        }
    }

    /// What the level does, in the user's words, for the card that describes it.
    public var points: [String] {
        switch self {
        case .relaxed: ["Trackers blocked", "Dangerous sites blocked", "Ads and cookie notices stay"]
        case .balanced: ["Ads and trackers blocked", "Cookie notices answered for you", "Cross-site cookies blocked"]
        case .strict: ["Everything in Balanced", "Pop-ups and anything ad-like hidden", "Secure connections only"]
        }
    }

    public var symbol: String {
        switch self {
        case .relaxed: "shield"
        case .balanced: "shield.lefthalf.filled"
        case .strict: "shield.fill"
        }
    }

    /// How much Shields does on a page at this level (`FilteringMode`).
    public var filteringMode: FilteringMode {
        switch self {
        case .relaxed: .basic
        case .balanced: .optimal
        case .strict: .complete
        }
    }

    /// Whether a profile's `settings` are this level's; `ignoringMode` for a settings file from
    /// before the filtering modes, which has none to compare.
    public func sets(_ settings: PrivacySettings, ignoringMode: Bool = false) -> Bool {
        var preset = settings
        apply(to: &preset)
        if ignoringMode { preset.filteringMode = settings.filteringMode }
        return preset == settings
    }

    /// Sets the switches the level owns; the others (the don't-sell signal, tracking codes,
    /// noticing fingerprinting, More lists) stay as they are.
    public func apply(to settings: inout PrivacySettings) {
        settings.filteringMode = filteringMode
        settings.blockTrackers = true
        settings.blockMaliciousSites = true
        settings.blockAds = self != .relaxed
        settings.blockCookieNotices = self != .relaxed
        settings.blockThirdPartyCookies = self != .relaxed
        settings.blockAnnoyances = self == .strict
        settings.httpsOnly = self == .strict
    }

    /// The level a profile's settings are, or nil when a switch was changed by hand.
    public static func level(of settings: PrivacySettings) -> PrivacyLevel? {
        allCases.first { $0.sets(settings) }
    }

    /// The Default profile's (`AppSettings.privacy`).
    public func sets(_ settings: AppSettings, ignoringMode: Bool = false) -> Bool { sets(settings.privacy, ignoringMode: ignoringMode) }
    public func apply(to settings: inout AppSettings) { apply(to: &settings.privacy) }
    public static func level(of settings: AppSettings) -> PrivacyLevel? { level(of: settings.privacy) }
}

public extension AppSettings {
    /// The Default profile's "Trackers" (`PrivacySettings.blockTrackers`).
    var blockTrackers: Bool {
        get { blockAdsAndTrackers }
        set { blockAdsAndTrackers = newValue }
    }

    /// The groups of filter lists the Default profile's switches ask for.
    var shieldsGroups: Set<ShieldsGroup> { privacy.shieldsGroups }
}

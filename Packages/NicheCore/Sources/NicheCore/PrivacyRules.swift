import Foundation

/// The user's own decisions in the privacy panel, on top of the tracker list: a company blocked or
/// allowed on one site or on all of them, and sites where nothing is blocked. Kept in privacy.json.
/// A party is a company's id from `TrackerDirectory` ("google"), or for a host the directory doesn't
/// know, its site ("ads.example").
public struct PrivacyRules: Codable, Equatable, Sendable {
    public var blocked: Set<String> = []
    public var allowed: Set<String> = []
    /// By the site of the page: the parties blocked or allowed there.
    public var blockedOn: [String: Set<String>] = [:]
    public var allowedOn: [String: Set<String>] = [:]
    /// Sites where protection is off: nothing is blocked there (`FilteringMode.none`).
    public var offSites: Set<String> = []
    /// Sites with a filtering mode of their own that isn't off (`FilteringMode`'s raw value).
    public var siteModes: [String: Int] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocked = try c.decodeIfPresent(Set<String>.self, forKey: .blocked) ?? []
        allowed = try c.decodeIfPresent(Set<String>.self, forKey: .allowed) ?? []
        blockedOn = try c.decodeIfPresent([String: Set<String>].self, forKey: .blockedOn) ?? [:]
        allowedOn = try c.decodeIfPresent([String: Set<String>].self, forKey: .allowedOn) ?? [:]
        offSites = try c.decodeIfPresent(Set<String>.self, forKey: .offSites) ?? []
        siteModes = try c.decodeIfPresent([String: Int].self, forKey: .siteModes) ?? [:]
    }

    /// What the user decided about a party, as the panel's menu shows it.
    public enum Choice: String, CaseIterable, Sendable {
        /// Nothing: the tracker list decides.
        case standard
        case blockedHere, blockedEverywhere, allowedHere, allowedEverywhere

        public var title: String {
            switch self {
            case .standard: "Let Niche Decide"
            case .blockedHere: "Block on This Site"
            case .blockedEverywhere: "Block Everywhere"
            case .allowedHere: "Allow on This Site"
            case .allowedEverywhere: "Allow Everywhere"
            }
        }
    }

    /// The choice in force for `party` on a page of `site`: the site's own comes before the one for
    /// every site, as the engine applies them.
    public func choice(for party: String, on site: String) -> Choice {
        if allowedOn[site]?.contains(party) == true { return .allowedHere }
        if blockedOn[site]?.contains(party) == true { return .blockedHere }
        if allowed.contains(party) { return .allowedEverywhere }
        if blocked.contains(party) { return .blockedEverywhere }
        return .standard
    }

    /// Makes `choice` the one in force for `party` on `site`. A choice for every site replaces the
    /// party's choices everywhere; a choice for this site leaves the others alone; `standard` clears
    /// what was in force here (and the choice for every site, if that was it).
    public mutating func set(_ choice: Choice, for party: String, on site: String) {
        func clearHere() {
            blockedOn[site]?.remove(party)
            allowedOn[site]?.remove(party)
            if blockedOn[site]?.isEmpty == true { blockedOn[site] = nil }
            if allowedOn[site]?.isEmpty == true { allowedOn[site] = nil }
        }
        func clearEverywhere() {
            blocked.remove(party)
            allowed.remove(party)
            for key in Array(blockedOn.keys) {
                blockedOn[key]?.remove(party)
                if blockedOn[key]?.isEmpty == true { blockedOn[key] = nil }
            }
            for key in Array(allowedOn.keys) {
                allowedOn[key]?.remove(party)
                if allowedOn[key]?.isEmpty == true { allowedOn[key] = nil }
            }
        }
        switch choice {
        case .standard:
            let was = self.choice(for: party, on: site)
            clearHere()
            if was == .blockedEverywhere || was == .allowedEverywhere { blocked.remove(party); allowed.remove(party) }
        case .blockedHere:
            clearHere()
            blockedOn[site, default: []].insert(party)
        case .allowedHere:
            clearHere()
            allowedOn[site, default: []].insert(party)
        case .blockedEverywhere:
            clearEverywhere()
            blocked.insert(party)
        case .allowedEverywhere:
            clearEverywhere()
            allowed.insert(party)
        }
    }

    public func isOff(on site: String) -> Bool { offSites.contains(site) }

    public mutating func setOff(_ off: Bool, on site: String) {
        if off { offSites.insert(site); siteModes[site] = nil } else { offSites.remove(site) }
    }

    /// The site's own filtering mode, or nil when it follows the one for every site.
    public func ownMode(on site: String) -> FilteringMode? {
        if offSites.contains(site) { return FilteringMode.none }
        return siteModes[site].flatMap(FilteringMode.init(rawValue:))
    }

    /// The mode in force on `site`: its own, else `standard`, the one for every site.
    public func mode(on site: String, standard: FilteringMode) -> FilteringMode { ownMode(on: site) ?? standard }

    /// Gives `site` a mode of its own. The mode every site has is no mode of its own: the site
    /// follows the setting again, also when the setting changes later.
    public mutating func setMode(_ mode: FilteringMode, on site: String, standard: FilteringMode) {
        offSites.remove(site)
        siteModes[site] = nil
        if mode == .none { offSites.insert(site) } else if mode != standard { siteModes[site] = mode.rawValue }
    }

    public var isEmpty: Bool { blocked.isEmpty && allowed.isEmpty && blockedOn.isEmpty && allowedOn.isEmpty && offSites.isEmpty && siteModes.isEmpty }

    /// The rules as the engine takes them: domains instead of parties, each list sorted.
    public struct Compiled: Equatable, Sendable {
        public var blocked: [String] = []
        public var allowed: [String] = []
        public var blockedOn: [String: [String]] = [:]
        public var allowedOn: [String: [String]] = [:]
        public var offSites: [String] = []
        /// Every site with a mode of its own, the off ones too (0).
        public var siteModes: [String: Int] = [:]

        public init(blocked: [String] = [], allowed: [String] = [], blockedOn: [String: [String]] = [:],
                    allowedOn: [String: [String]] = [:], offSites: [String] = [], siteModes: [String: Int] = [:]) {
            self.blocked = blocked
            self.allowed = allowed
            self.blockedOn = blockedOn
            self.allowedOn = allowedOn
            self.offSites = offSites
            self.siteModes = siteModes
        }
    }

    /// A company stands for every domain the directory lists for it; any other party is the site
    /// itself.
    public func compiled(directory: TrackerDirectory = .standard) -> Compiled {
        func domains(_ parties: Set<String>) -> [String] {
            Array(Set(parties.flatMap { party -> [String] in
                directory.company(party) != nil ? directory.domains(of: party) : [party]
            })).sorted()
        }
        return Compiled(blocked: domains(blocked), allowed: domains(allowed),
                        blockedOn: blockedOn.mapValues(domains), allowedOn: allowedOn.mapValues(domains),
                        offSites: offSites.sorted(),
                        siteModes: siteModes.merging(offSites.map { ($0, FilteringMode.none.rawValue) }) { _, off in off })
    }
}

/// The privacy panel's choices for every browser profile (privacy.json), by `PrivacyProfile.key`:
/// a site switched off or a company allowed in one profile is not in any other (22 Nov 2026).
/// The Default profile's are at the top of the file, where every version has read them; the
/// others under `profiles`.
public struct PrivacyRuleBook: Codable, Equatable, Sendable {
    private var byProfile: [String: PrivacyRules] = [:]
    /// Read from a file from before each profile had its own: its one set was every profile's.
    public private(set) var sharedByEveryProfile = false

    public init() {}

    private enum CodingKeys: String, CodingKey { case profiles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mine = try PrivacyRules(from: decoder)
        if mine != PrivacyRules() { byProfile[PrivacyProfile.defaultKey] = mine }
        for (key, rules) in (try? c.decodeIfPresent([String: PrivacyRules].self, forKey: .profiles)) ?? [:]
        where key != PrivacyProfile.defaultKey && rules != PrivacyRules() {
            byProfile[key] = rules
        }
        sharedByEveryProfile = !c.contains(.profiles)
    }

    public func encode(to encoder: Encoder) throws {
        try self[PrivacyProfile.defaultKey].encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(byProfile.filter { $0.key != PrivacyProfile.defaultKey }, forKey: .profiles)
    }

    /// A profile's choices; none for one that has made none.
    public subscript(profile: String) -> PrivacyRules {
        get { byProfile[profile] ?? PrivacyRules() }
        set { byProfile[profile] = newValue == PrivacyRules() ? nil : newValue }
    }

    /// The profiles with choices of their own.
    public var profiles: Set<String> { Set(byProfile.keys) }

    /// After a file from before per-profile choices: each profile gets the one set there was, so
    /// nothing changes on update. A profile made since starts with none. The choices of profiles
    /// that are gone are forgotten. `profiles`: the keys of the profiles there are besides Default.
    public mutating func adopt(profiles: Set<String>) {
        if sharedByEveryProfile {
            let shared = self[PrivacyProfile.defaultKey]
            for key in profiles where key != PrivacyProfile.defaultKey { self[key] = shared }
            sharedByEveryProfile = false
        }
        for key in byProfile.keys where key != PrivacyProfile.defaultKey && !profiles.contains(key) { byProfile[key] = nil }
    }
}

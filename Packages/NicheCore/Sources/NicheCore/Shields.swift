import CryptoKit
import Foundation

/// What a filter list is for: one switch in Settings ▸ Privacy each, except `core`, which keeps
/// sites working (exceptions and fixes) and is used whenever anything is.
public enum ShieldsGroup: String, Codable, CaseIterable, Sendable {
    case core, ads, trackers, cookies, annoyances, malware, regional

    /// The number the engine hands back with a blocked request (`NichePrivacyEvent.group`).
    public var number: Int { Self.allCases.firstIndex(of: self)! }

    public init?(number: Int) {
        guard Self.allCases.indices.contains(number) else { return nil }
        self = Self.allCases[number]
    }

    /// The switch's name.
    public var title: String {
        switch self {
        case .core: "Site fixes"
        case .ads: "Ads"
        case .trackers: "Trackers"
        case .cookies: "Cookie notices"
        case .annoyances: "Pop-ups and nags"
        case .malware: "Dangerous sites"
        case .regional: "Lists for your languages"
        }
    }

    /// One plain sentence under the switch.
    public var detail: String {
        switch self {
        case .core: "Exceptions and fixes that keep pages working."
        case .ads: "Banners, video ads and sponsored slots are blocked, and the gaps they leave are closed."
        case .trackers: "Companies that follow you from site to site are cut off before they hear of a visit."
        case .cookies: "Cookie notices are answered with “essential only” where Niche knows the site, and hidden elsewhere."
        case .annoyances: "Newsletter pop-ups and “allow notifications?” prompts that sites put in front of the page."
        case .malware: "Sites and files known to spread malware are not loaded."
        case .regional: "Extra lists for sites in the languages this Mac uses."
        }
    }

    /// The SF Symbol beside the switch.
    public var symbol: String {
        switch self {
        case .core: "wrench.and.screwdriver"
        case .ads: "rectangle.slash"
        case .trackers: "eye.slash"
        case .cookies: "checkmark.rectangle.stack"
        case .annoyances: "bell.slash"
        case .malware: "exclamationmark.shield"
        case .regional: "globe"
        }
    }

    /// What the privacy panel says blocked a request ("on the tracker lists").
    public var listsWords: String {
        switch self {
        case .core: "on the lists"
        case .ads: "on the ad lists"
        case .trackers: "on the tracker lists"
        case .cookies: "on the cookie-notice lists"
        case .annoyances: "on the pop-up lists"
        case .malware: "on the dangerous-site lists"
        case .regional: "on a list for your language"
        }
    }
}

/// A Shields pack: what Niche downloads (scripts/shields-pack.mjs builds and signs
/// it): filter lists with what each is for, and the scriptlets and stand-in resources the
/// engine needs beside them. The file is raw-deflated JSON with a detached Ed25519 signature.
public struct ShieldsPack: Equatable, Sendable {
    public struct List: Equatable, Sendable {
        public var id: String
        public var group: ShieldsGroup
        public var title: String
        public var licence: String
        public var homepage: String
        /// May use the scriptlets that set cookies and storage (uBlock Origin's own lists).
        public var trusted: Bool
        /// For a regional list: the languages it is for ("de", "fr").
        public var languages: [String]
        public var text: Data

        public init(id: String, group: ShieldsGroup, title: String = "", licence: String = "", homepage: String = "",
                    trusted: Bool = false, languages: [String] = [], text: Data) {
            self.id = id
            self.group = group
            self.title = title
            self.licence = licence
            self.homepage = homepage
            self.trusted = trusted
            self.languages = languages
            self.text = text
        }
    }

    /// The format this build of Niche reads.
    public static let format = 1
    /// The key the packs are signed with (Ed25519, base64 of the 32 raw bytes). The private half
    /// is a secret of the repository's "Shields" workflow.
    public static let publicKey = "t+Z2hg3f0/To298fGL71bIXByrQIcaYREHoRer3eL9Y="

    public var built: Date?
    public var lists: [List] = []
    /// adblock-rust resources as JSON arrays: the scriptlets list rules inject, and the
    /// stand-ins served for blocked requests. Empty when the pack has none.
    public var scriptlets = Data()
    public var redirects = Data()

    public init(built: Date? = nil, lists: [List] = [], scriptlets: Data = Data(), redirects: Data = Data()) {
        self.built = built
        self.lists = lists
        self.scriptlets = scriptlets
        self.redirects = redirects
    }

    public enum Failure: Error, Equatable { case notAPack, newerFormat(Int) }

    /// Whether `signature` (base64) is the key's over `file`: a download that fails this is
    /// thrown away.
    public static func isSigned(_ file: Data, signature: String, key: String = publicKey) -> Bool {
        guard let raw = Data(base64Encoded: key), let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return publicKey.isValidSignature(sig, for: file)
    }

    /// Reads a pack file. A list whose group this build doesn't know is skipped, so a newer
    /// pack with a new kind of list still loads.
    public static func read(_ file: Data) throws -> ShieldsPack {
        guard let json = try? (file as NSData).decompressed(using: .zlib) as Data,
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let version = root["format"] as? Int, let entries = root["lists"] as? [[String: Any]] else { throw Failure.notAPack }
        guard version <= format else { throw Failure.newerFormat(version) }
        var pack = ShieldsPack()
        if let built = root["built"] as? String { pack.built = ISO8601DateFormatter.fractional.date(from: built) ?? ISO8601DateFormatter().date(from: built) }
        for entry in entries {
            guard let id = entry["id"] as? String, let text = entry["text"] as? String,
                  let group = (entry["group"] as? String).flatMap(ShieldsGroup.init(rawValue:)) else { continue }
            pack.lists.append(List(id: id, group: group, title: entry["title"] as? String ?? id, licence: entry["licence"] as? String ?? "",
                                   homepage: entry["homepage"] as? String ?? "", trusted: entry["trusted"] as? Bool ?? false,
                                   languages: entry["languages"] as? [String] ?? [], text: Data(text.utf8)))
        }
        if let resources = root["resources"] as? [String: Any] {
            for (key, path) in [("scriptlets", \ShieldsPack.scriptlets), ("redirects", \ShieldsPack.redirects)] {
                if let array = resources[key] as? [Any], !array.isEmpty, let data = try? JSONSerialization.data(withJSONObject: array) {
                    pack[keyPath: path] = data
                }
            }
        }
        return pack
    }

    /// The lists to build the engine from when these groups are switched on: theirs, and the
    /// core lists as soon as there is one of them. Nothing on: nothing.
    public func lists(for groups: Set<ShieldsGroup>) -> [List] {
        let wanted = lists.filter { $0.group != .core && groups.contains($0.group) }
        return wanted.isEmpty ? [] : lists.filter { $0.group == .core } + wanted
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// The regional packs there are (shields-regional.json beside the packs), and which of them a
/// Mac wants.
public struct ShieldsRegionalIndex: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var languages: [String]
    }

    public var lists: [Entry] = []

    public init(lists: [Entry] = []) { self.lists = lists }

    /// The lists for these languages ("de-CH", "fr"): a list is wanted when one of its languages
    /// is among them. English has no list of its own (the main lists are English's).
    public func wanted(languages: [String]) -> [Entry] {
        let spoken = Set(languages.compactMap { $0.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } })
        return lists.filter { !spoken.isDisjoint(with: $0.languages) }
    }
}

/// The optional lists there are (shields-lists.json beside the packs): the ones Settings ▸
/// Privacy "More lists" offers, each a small pack of its own that a Mac fetches when its switch
/// goes on. They are uBlock Origin Lite's optional rulesets, read from its own catalogue when
/// the packs are built, so a list it adds or drops is added or dropped here, and the lists Niche
/// offers on top (AdGuard's ad list).
public struct ShieldsCatalog: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        /// What the list is for: the name of a `ShieldsGroup` ("ads", "trackers", "annoyances").
        public var group: String
        public var homepage: String
        /// One plain sentence, when the catalogue has one.
        public var detail: String

        public init(id: String, title: String, group: String = "ads", homepage: String = "", detail: String = "") {
            self.id = id
            self.title = title
            self.group = group
            self.homepage = homepage
            self.detail = detail
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? id
            group = try c.decodeIfPresent(String.self, forKey: .group) ?? "ads"
            homepage = try c.decodeIfPresent(String.self, forKey: .homepage) ?? ""
            detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        }

        public var shieldsGroup: ShieldsGroup { ShieldsGroup(rawValue: group) ?? .ads }
    }

    public var lists: [Entry] = []

    public init(lists: [Entry] = []) { self.lists = lists }

    /// The entries switched on, in the catalogue's order. A switch for a list the catalogue no
    /// longer has asks for nothing.
    public func wanted(_ ids: Set<String>) -> [Entry] { lists.filter { ids.contains($0.id) } }

    /// The catalogue as Settings shows it: by what the lists are for, in `ShieldsGroup`'s order.
    public var sections: [(group: ShieldsGroup, entries: [Entry])] {
        ShieldsGroup.allCases.compactMap { group in
            let entries = lists.filter { $0.shieldsGroup == group }
            return entries.isEmpty ? nil : (group, entries)
        }
    }
}

/// When Niche looks for newer packs, and the names it asks for.
public enum ShieldsUpdate {
    /// Where the packs are published: assets of the repository's "shields" release.
    public static let source = "https://github.com/niche-browser/niche/releases/download/shields/"
    public static let mainPack = "shields.pack"
    public static let regionalIndex = "shields-regional.json"
    public static let catalog = "shields-lists.json"
    /// Every six hours, as often as the packs are built (uBlock Origin's quick fixes for sites
    /// that fight ad blockers expire after eight), and a failed look is tried again after an hour.
    public static let interval: TimeInterval = 6 * 3600
    public static let retry: TimeInterval = 3600

    public static func regionalPack(_ id: String) -> String { "shields-\(id).pack" }
    /// An optional list's pack. Its name can't be a regional one's: their ids have no "x-".
    public static func extraPack(_ id: String) -> String { "shields-x-\(id).pack" }

    /// Whether to look now, having last looked (or tried) at these times.
    public static func isDue(lastSuccess: Date?, lastAttempt: Date?, now: Date) -> Bool {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < retry { return false }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= interval
    }
}

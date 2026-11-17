import Foundation

/// One thing a page did that concerns the visitor's privacy, as the engine reports it
/// (NichePrivacyEvent) or as the page's own script does (a fingerprinting probe).
public struct PrivacyEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The tab asked for another page: the ledger starts over.
        case navigation
        /// A request to another site than the page's.
        case request
        /// A cookie that went out with such a request, or that its answer left behind.
        case cookieSent, cookieSaved
        /// Click identifiers were taken off the page's address.
        case cleanedAddress
        /// A script read something that tells this Mac from others.
        case probe(PrivacyProbe)
    }

    public enum Verdict: Int, Equatable, Sendable {
        case allowed = 0, blockedByList = 1, blockedByUser = 2
        public var blocked: Bool { self != .allowed }
    }

    public var kind: Kind
    /// The host asked (or the host a probing script came from) and its site.
    public var host: String
    public var site: String
    public var resource = ""
    public var verdict = Verdict.allowed
    /// On the ad and tracker list.
    public var listed = false
    /// The request said which site it came from, and which page.
    public var sendsSite = false
    public var sendsPage = false
    public var bytesSent: Int64 = 0
    /// A cookie's name.
    public var detail = ""
    /// How long a saved cookie lasts; 0 until the browser quits.
    public var cookieDays: Double = 0
    /// Tells one address from another without naming it (a hash of it); 0 when there is none.
    public var key: UInt64 = 0
    /// For a request the filter lists blocked: what the list that did is for.
    public var group: ShieldsGroup?
    public var at: Date

    public init(kind: Kind, host: String, site: String, at: Date) {
        self.kind = kind
        self.host = host
        self.site = site
        self.at = at
    }
}

/// What one tab's page has done since it was asked for: who it talked to, what each of them got,
/// and what Niche stopped. Built from `PrivacyEvent`s; the panel draws `summary`, `sorted` and `feed`.
public struct PrivacyLedger: Equatable, Sendable {
    /// A company the page reached out to (or a site, when the directory doesn't know whose it is).
    public struct Party: Equatable, Sendable, Identifiable {
        /// The company's id, or the site.
        public let id: String
        public var name: String
        /// Whether the directory knows the company (otherwise `name` is the site).
        public var known: Bool
        /// What its hosts on this page are for, worst first.
        public var categories: [TrackerCategory] = []
        public var hosts: Set<String> = []
        public var blocked = 0
        public var allowed = 0
        /// Blocked by the user's own rule (rather than the list).
        public var blockedByUser = false
        /// What the lists that blocked it are for (ads, trackers, …).
        public var blockedBy: Set<ShieldsGroup> = []
        public var listed = false
        public var sawSite = false
        public var sawPage = false
        public var bytesSent: Int64 = 0
        public var cookiesSent: Set<String> = []
        /// Cookies it left, by name, with how many days each lasts (0: until the browser quits).
        public var cookiesSaved: [String: Double] = [:]
        /// Cookies Niche held back: ones it asked to get or to leave, as a third party.
        public var cookiesWithheld: Set<String> = []
        /// What the hosts that got through are for, and whether one of them is on the list:
        /// a company whose trackers were blocked doesn't see the visit through its fonts.
        public var allowedCategories: Set<TrackerCategory> = []
        public var allowedListed = false
        public var probes: Set<PrivacyProbe> = []
        /// The company that runs the site the page is on (Google on youtube.com): it is the site,
        /// not somebody else watching it.
        public var ownsSite = false
        public var lastSeen: Date

        public init(id: String, name: String, known: Bool, lastSeen: Date) {
            self.id = id
            self.name = name
            self.known = known
            self.lastSeen = lastSeen
        }

        public enum Status: Equatable, Sendable { case blocked, partly, allowed }

        /// Blocked when nothing of it got through; partly when some did.
        public var status: Status {
            if allowed == 0, probes.isEmpty { return blocked > 0 ? .blocked : .allowed }
            return blocked > 0 ? .partly : .allowed
        }

        /// Where the panel lists it: with the trackers that can see the visit, with what was kept
        /// out, or with the rest. The site's own company is always with the rest, whatever of
        /// its own was blocked: the site is not kept out of its own page.
        public enum Listing: Equatable, Sendable { case seesYou, blocked, other }

        public var listing: Listing {
            if ownsSite { return .other }
            if sawYou { return .seesYou }
            return status == .blocked ? .blocked : .other
        }

        public var category: TrackerCategory { categories.first ?? .unknown }
        /// There to learn about the visitor, rather than to make the page work.
        public var tracks: Bool { listed || categories.contains(where: \.tracks) || !probes.isEmpty }
        /// Something of it that tracks got through: the visit is known to it.
        /// So is a party nobody can name that got a cookie back: it knows it is you again.
        public var sawYou: Bool {
            guard !ownsSite else { return false }
            return !probes.isEmpty || allowedListed || allowedCategories.contains(where: \.tracks) || (!known && !cookiesSent.isEmpty)
        }

        /// What Niche kept from it though it got through; nil when nothing.
        public var withheld: String? {
            cookiesWithheld.isEmpty ? nil
                : "Niche kept \(PrivacyWords.count(cookiesWithheld.count, "cookie")) from it, so it can’t tell it is you again."
        }
        public var requests: Int { blocked + allowed }

        /// Why its requests were blocked, for the row's details: "Blocked because it is on the
        /// ad lists and the tracker lists." / "You blocked it."; nil when nothing was.
        public var blockedWhy: String? {
            guard blocked > 0 else { return nil }
            let lists = ShieldsGroup.allCases.filter(blockedBy.contains).map(\.listsWords)
            let named = lists.map { $0.replacingOccurrences(of: "on ", with: "", options: .anchored) }
            switch (blockedByUser, named.isEmpty) {
            case (true, true): return "You blocked it."
            case (true, false): return "You blocked it, and it is on \(PrivacyWords.list(named))."
            case (false, true): return "Blocked by the filter lists."
            case (false, false): return "Blocked because it is on \(PrivacyWords.list(named))."
            }
        }

        /// What it learned from this visit, one plain line each, the most telling first. Empty for
        /// a party that was blocked outright.
        public func learned(pageSite: String) -> [String] {
            guard status != .blocked else { return [] }
            var lines: [String] = []
            for probe in PrivacyProbe.allCases where probes.contains(probe) { lines.append("Read \(probe.what)") }
            if !cookiesSent.isEmpty {
                lines.append("Knows it is you again (\(PrivacyWords.count(cookiesSent.count, "cookie")) it left went back to it)")
            }
            if allowed > 0 {
                if sawPage {
                    lines.append("The exact page you are on")
                } else if sawSite {
                    lines.append("That you are on \(pageSite)")
                }
                lines.append("Your internet address, which shows roughly where you are")
            }
            if bytesSent > 0 { lines.append("Data the page sent it (\(DownloadRow.bytes(bytesSent)))") }
            if let longest = cookiesSaved.values.max() {
                let n = cookiesSaved.count
                lines.append("Left \(PrivacyWords.count(n, "cookie")) on this Mac, kept \(PrivacyWords.duration(days: longest))")
            }
            return lines
        }
    }

    /// One line of the live feed. There is one per party and kind of thing: a repeat counts up
    /// and moves to the end, so the feed reads as a list of what happened, not a log.
    public struct FeedItem: Equatable, Sendable, Identifiable {
        public enum Tone: Equatable, Sendable { case blocked, saw, neutral, cleaned }
        public let id: String
        public var title: String
        public var detail: String
        public var tone: Tone
        public var count: Int
        public var at: Date
    }

    public struct Summary: Equatable, Sendable {
        /// Companies the page reached out to.
        public var parties = 0
        /// Stopped before they heard of the visit.
        public var blocked = 0
        /// Trackers that got through.
        public var sawYou = 0
        /// The rest: what makes the page work, and what Niche can't name.
        public var others = 0
        public var blockedRequests = 0
        /// Requests to other sites that went out.
        public var allowedRequests = 0
        /// Cookies held back from the companies that got through.
        public var cookiesWithheld = 0
        /// Cookies other sites got back or left.
        public var cookiesPassed = 0
        /// Companies seen reading what tells this Mac from others.
        public var fingerprinters = 0
        public var cleanedAddress = false
        /// How many companies of each kind, worst kind first.
        public var kinds: [Kind] = []

        public struct Kind: Equatable, Sendable, Identifiable {
            public var category: TrackerCategory
            public var count: Int
            public var id: TrackerCategory { category }
            public init(category: TrackerCategory, count: Int) {
                self.category = category
                self.count = count
            }
        }

        public init(parties: Int = 0, blocked: Int = 0, sawYou: Int = 0, others: Int = 0, blockedRequests: Int = 0, allowedRequests: Int = 0,
                    cookiesWithheld: Int = 0, cookiesPassed: Int = 0, fingerprinters: Int = 0, cleanedAddress: Bool = false, kinds: [Kind] = []) {
            self.parties = parties
            self.blocked = blocked
            self.sawYou = sawYou
            self.others = others
            self.blockedRequests = blockedRequests
            self.allowedRequests = allowedRequests
            self.cookiesWithheld = cookiesWithheld
            self.cookiesPassed = cookiesPassed
            self.fingerprinters = fingerprinters
            self.cleanedAddress = cleanedAddress
            self.kinds = kinds
        }

        /// The panel's headline.
        public var headline: String {
            if parties == 0 { return cleanedAddress ? "A tracking code was removed from this page’s address" : "This page hasn’t contacted anyone else" }
            if sawYou == 0 { return blocked == 0 ? "No trackers on this page" : "Every tracker on this page was blocked" }
            return "\(PrivacyWords.count(sawYou, "tracker")) can see this visit"
        }
    }

    public private(set) var pageSite: String
    public private(set) var parties: [String: Party] = [:]
    public private(set) var feed: [FeedItem] = []
    public private(set) var cleanedAddress = false
    /// The addresses blocked on this page (by `PrivacyEvent.key`): a page asks again for what it
    /// didn't get, and that is still one thing blocked.
    private var blockedKeys: Set<UInt64> = []
    public private(set) var started: Date
    /// The feed keeps this many lines, the newest.
    public static let feedLimit = 40
    /// Blocked addresses remembered per page.
    public static let blockedKeyLimit = 4000
    /// Hosts and cookie names remembered per company (a page can make up new ones all day).
    public static let nameLimit = 200

    public init(pageSite: String = "", started: Date = .distantPast) {
        self.pageSite = pageSite
        self.started = started
    }

    public var isEmpty: Bool { parties.isEmpty && !cleanedAddress }

    /// Starts over for a page of `site` (a committed page of another site than the ledger's, where
    /// no request announced it: a page restored from the back-forward cache).
    public mutating func reset(pageSite site: String, at: Date) {
        self = PrivacyLedger(pageSite: site, started: at)
    }

    public mutating func record(_ e: PrivacyEvent, directory: TrackerDirectory = .standard) {
        switch e.kind {
        case .navigation:
            reset(pageSite: e.site, at: e.at)
            return
        case .cleanedAddress:
            cleanedAddress = true
            note(id: "cleaned", title: "Tracking code removed", detail: "From this page’s address", tone: .cleaned, at: e.at)
            return
        default:
            break
        }
        if e.kind == .request, e.verdict.blocked, e.key != 0 {
            if blockedKeys.contains(e.key) { return }
            // A page that asks for ever (a new address every few seconds) is told apart up to here;
            // past it a repeat may count again, which is better than a list that grows all day.
            if blockedKeys.count < Self.blockedKeyLimit { blockedKeys.insert(e.key) }
        }
        let match = directory.match(host: e.host)
        let id = match?.company.id ?? e.site
        var party = parties[id] ?? Party(id: id, name: match?.company.name ?? e.site, known: match != nil, lastSeen: e.at)
        party.lastSeen = e.at
        // The site's own company, or the site itself (an ad it serves from its own address).
        if id == pageSite || (match != nil && directory.match(host: pageSite)?.company.id == id) { party.ownsSite = true }
        if party.hosts.count < Self.nameLimit { party.hosts.insert(e.host) }
        if e.listed { party.listed = true }
        let category = match?.category ?? (e.listed ? .tracker : .unknown)
        if !party.categories.contains(category) { party.categories = (party.categories + [category]).sorted() }
        // Unidentified is what a party is until something better is known about it.
        if party.categories.count > 1 { party.categories.removeAll { $0 == .unknown } }
        let name = party.name
        switch e.kind {
        case .request:
            if e.verdict.blocked {
                party.blocked += 1
                if e.verdict == .blockedByUser { party.blockedByUser = true }
                if let group = e.group { party.blockedBy.insert(group) }
                // The site's own address: it is what the site serves that was stopped, not the site.
                note(id: id + ":blocked", title: id == pageSite ? "Blocked ads or trackers from this site" : "Blocked \(name)",
                     detail: category.title, tone: .blocked, at: e.at)
            } else {
                party.allowed += 1
                party.allowedCategories.insert(category)
                if e.listed { party.allowedListed = true }
                party.sawSite = party.sawSite || e.sendsSite
                party.sawPage = party.sawPage || e.sendsPage
                party.bytesSent += e.bytesSent
                let tracks = e.listed || category.tracks
                note(id: id + ":allowed", title: tracks ? "\(name) saw this visit" : "\(name) loaded", detail: category.title,
                     tone: tracks ? .saw : .neutral, at: e.at)
            }
        case .cookieSent where e.verdict.blocked, .cookieSaved where e.verdict.blocked:
            if party.cookiesWithheld.count < Self.nameLimit, party.cookiesWithheld.insert(e.detail).inserted {
                note(id: id + ":withheld", title: "Kept cookies from \(name)", detail: "It can’t tell it is you again", tone: .blocked, at: e.at)
            }
        case .cookieSent:
            if party.cookiesSent.count < Self.nameLimit, party.cookiesSent.insert(e.detail).inserted {
                note(id: id + ":recognised", title: "\(name) recognised you", detail: "A cookie it left went back to it", tone: .saw, at: e.at,
                     counts: false)
            }
        case .cookieSaved:
            let fresh = party.cookiesSaved[e.detail] == nil
            if fresh, party.cookiesSaved.count >= Self.nameLimit { break }
            party.cookiesSaved[e.detail] = max(party.cookiesSaved[e.detail] ?? 0, e.cookieDays)
            if fresh {
                note(id: id + ":cookie", title: "\(name) left a cookie", detail: "Kept " + PrivacyWords.duration(days: party.cookiesSaved.values.max() ?? 0),
                     tone: category.tracks || e.listed ? .saw : .neutral, at: e.at, counts: false)
            }
        case .probe(let probe):
            if party.probes.insert(probe).inserted {
                if !party.categories.contains(.fingerprinting) { party.categories = (party.categories + [.fingerprinting]).sorted() }
                party.categories.removeAll { $0 == .unknown }
                note(id: id + ":probe:" + probe.rawValue, title: "\(name) read \(probe.what)", detail: TrackerCategory.fingerprinting.title,
                     tone: .saw, at: e.at, counts: false)
            }
        case .navigation, .cleanedAddress:
            break
        }
        parties[id] = party
    }

    /// One line per id: a repeat moves it to the end with its latest words, and counts up when
    /// the thing is countable (requests are, a cookie's arrival is not).
    private mutating func note(id: String, title: String, detail: String, tone: FeedItem.Tone, at: Date, counts: Bool = true) {
        if let i = feed.firstIndex(where: { $0.id == id }) {
            var item = feed.remove(at: i)
            item.title = title
            item.detail = detail
            item.tone = tone
            if counts { item.count += 1 }
            item.at = at
            feed.append(item)
        } else {
            feed.append(FeedItem(id: id, title: title, detail: detail, tone: tone, count: 1, at: at))
            if feed.count > Self.feedLimit { feed.removeFirst(feed.count - Self.feedLimit) }
        }
    }

    public var summary: Summary {
        var s = Summary(cleanedAddress: cleanedAddress)
        var kinds: [TrackerCategory: Int] = [:]
        for p in parties.values {
            s.parties += 1
            s.blockedRequests += p.blocked
            s.allowedRequests += p.allowed
            s.cookiesWithheld += p.cookiesWithheld.count
            s.cookiesPassed += p.cookiesSent.union(p.cookiesSaved.keys).count
            if !p.probes.isEmpty { s.fingerprinters += 1 }
            kinds[p.category, default: 0] += 1
            switch p.listing {
            case .blocked: s.blocked += 1
            case .seesYou: s.sawYou += 1
            case .other: s.others += 1
            }
        }
        s.kinds = kinds.map { Summary.Kind(category: $0.key, count: $0.value) }.sorted { $0.category < $1.category }
        return s
    }

    /// The parties in the order the panel lists them: those that can see the visit, then the ones
    /// blocked, then what makes the page work; in each group the worst kind first, then by name.
    public var sorted: [Party] {
        func group(_ p: Party) -> Int { p.listing == .seesYou ? 0 : p.listing == .blocked ? 1 : 2 }
        return parties.values.sorted { a, b in
            if group(a) != group(b) { return group(a) < group(b) }
            if a.category != b.category { return a.category < b.category }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

/// Small pieces of the panel's wording.
public enum PrivacyWords {
    /// "a", "a and b", "a, b and c".
    public static func list(_ items: [String]) -> String {
        items.count < 2 ? items.first ?? "" : items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    /// "1 cookie", "3 cookies".
    public static func count(_ n: Int, _ noun: String, plural: String? = nil) -> String { "\(n) \(n == 1 ? noun : plural ?? noun + "s")" }

    /// How long a cookie lasts, the way one would say it: "until you quit Niche", "for a day",
    /// "for 3 weeks", "for 13 months", "for 2 years".
    public static func duration(days: Double) -> String {
        if days <= 0 { return "until you quit Niche" }
        if days < 1 { return "for less than a day" }
        let d = Int(days.rounded())
        if d < 14 { return d == 1 ? "for a day" : "for \(d) days" }
        if d < 60 { return "for \(Int((Double(d) / 7).rounded())) weeks" }
        if d < 730 { return "for \(Int((Double(d) / 30.4).rounded())) months" }
        return "for \(Int((Double(d) / 365).rounded())) years"
    }

    /// What the panel says under a party the user decided about; nil when the list decides.
    public static func said(_ choice: PrivacyRules.Choice, name: String) -> String? {
        switch choice {
        case .standard: nil
        case .blockedHere: "You blocked \(name) on this site."
        case .blockedEverywhere: "You blocked \(name) on every site."
        case .allowedHere: "You allowed \(name) on this site."
        case .allowedEverywhere: "You allowed \(name) on every site."
        }
    }

    /// What else stops when a whole company is blocked: a company is blocked with everything the
    /// directory lists for it, and some of that makes pages work. nil when it has nothing of the
    /// kind (a pure tracker); for a party the directory doesn't know, that the page may need it.
    public static func blockCaveat(party: String, name: String, tracks: Bool, directory: TrackerDirectory = .standard) -> String? {
        guard directory.company(party) != nil else { return tracks ? nil : "The page may not work without it." }
        let things = directory.categories(of: party).compactMap { category -> String? in
            switch category {
            case .hosting: "fonts"
            case .media: "videos"
            case .security: "sign-in"
            case .payments: "payments"
            case .support: "chat"
            case .consent: "cookie notice"
            default: nil
            }
        }
        guard !things.isEmpty else { return nil }
        let list = things.count == 1 ? things[0] : things.dropLast().joined(separator: ", ") + " and " + things[things.count - 1]
        return "Blocking \(name) also stops its \(list) on pages that use them."
    }

    /// The word on a party's row for where it stands.
    public static func status(_ party: PrivacyLedger.Party) -> String {
        if party.ownsSite { return "This site" }
        switch party.status {
        case .blocked: return "Blocked"
        case .partly: return "Partly blocked"
        case .allowed: return party.sawYou ? "Sees you" : "Allowed"
        }
    }

    /// The toolbar button's help and VoiceOver label for a page.
    public static func shieldLabel(blocked: Int, sawYou: Int?) -> String {
        var s = blocked == 0 ? "Privacy: nothing blocked on this page" : "Privacy: \(blocked) blocked on this page"
        if let sawYou, sawYou > 0 { s += ", \(count(sawYou, "tracker")) can see this visit" }
        return s
    }

    /// The count on the toolbar button: nothing for none, "99+" past two digits.
    public static func badge(_ blocked: Int) -> String {
        blocked <= 0 ? "" : blocked > 99 ? "99+" : "\(blocked)"
    }
}

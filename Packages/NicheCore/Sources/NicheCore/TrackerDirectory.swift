import Foundation

/// What a third party on a page is there for, in the words the privacy panel uses. The order is
/// how much it matters to someone who wants to be left alone: the panel lists the worst first.
public enum TrackerCategory: String, Codable, CaseIterable, Sendable, Comparable {
    case sessionRecording, fingerprinting, dataBroker, advertising, tracker, social, analytics, marketing
    case security, payments, support, consent, media, hosting, unknown

    public var title: String {
        switch self {
        case .sessionRecording: "Screen recording"
        case .fingerprinting: "Device fingerprinting"
        case .dataBroker: "Data broker"
        case .advertising: "Advertising"
        case .tracker: "Ad or tracker"
        case .social: "Social media"
        case .analytics: "Analytics"
        case .marketing: "Marketing"
        case .security: "Sign-in and security"
        case .payments: "Payments"
        case .support: "Chat and support"
        case .consent: "Cookie notice"
        case .media: "Video and embeds"
        case .hosting: "Site delivery"
        case .unknown: "Unidentified"
        }
    }

    /// One plain sentence: what this kind of company does with a visit.
    public var explanation: String {
        switch self {
        case .sessionRecording: "Records your clicks, scrolling and typing so the visit can be replayed later."
        case .fingerprinting: "Recognises your Mac by its details, with no cookie needed."
        case .dataBroker: "Links your visits across many sites into one profile it sells or shares."
        case .advertising: "Follows what you look at to choose the ads you see."
        case .tracker: "On the list of known ad and tracker domains."
        case .social: "Lets a social network see which pages you visit."
        case .analytics: "Measures what you do on the site for its owner."
        case .marketing: "Email and sales tools that tie a visit to a person."
        case .security: "Signs you in or checks that you are a person."
        case .payments: "Takes a payment or checks it for fraud."
        case .support: "The site’s chat or help window."
        case .consent: "The site’s cookie notice."
        case .media: "Plays a video, a map or other embedded content."
        case .hosting: "Delivers the site's files, fonts or images."
        case .unknown: "Niche doesn’t know this one. It isn’t on the tracker list."
        }
    }

    /// The SF Symbol beside the category.
    public var symbol: String {
        switch self {
        case .sessionRecording: "record.circle"
        case .fingerprinting: "touchid"
        case .dataBroker: "person.2.wave.2"
        case .advertising: "megaphone"
        case .tracker: "eye"
        case .social: "bubble.left.and.bubble.right"
        case .analytics: "chart.bar"
        case .marketing: "envelope"
        case .security: "lock.shield"
        case .payments: "creditcard"
        case .support: "questionmark.bubble"
        case .consent: "checkmark.shield"
        case .media: "play.rectangle"
        case .hosting: "shippingbox"
        case .unknown: "questionmark.circle"
        }
    }

    /// Whether it is there to learn about the visitor, rather than to make the page work.
    public var tracks: Bool {
        switch self {
        case .sessionRecording, .fingerprinting, .dataBroker, .advertising, .tracker, .social, .analytics, .marketing: true
        case .security, .payments, .support, .consent, .media, .hosting, .unknown: false
        }
    }

    public static func < (a: TrackerCategory, b: TrackerCategory) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// Who owns the domains pages talk to. Written by hand for Niche (no third-party dataset, so no
/// licence comes with it): the companies seen most often on the web, not all of them, and only
/// domains whose owner is well known. Correct a row when a company sells or renames a product. A domain covers its
/// subdomains, and the most specific entry wins ("maps.googleapis.com" before "googleapis.com").
/// A host that matches nothing is shown under its own site name.
public struct TrackerDirectory: Sendable {
    public struct Company: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
    }

    public struct Match: Equatable, Sendable {
        public let company: Company
        public let category: TrackerCategory
        /// The entry that matched, which covers the host.
        public let domain: String
    }

    private let companies: [String: Company]
    private let byDomain: [String: (company: String, category: TrackerCategory)]
    private let domainsByCompany: [String: [String]]

    public static let standard = TrackerDirectory(rows: TrackerDirectoryData.rows)

    /// `rows`: a company's id, its name, a category and the domains it uses for that.
    public init(rows: [(id: String, name: String, category: TrackerCategory, domains: [String])]) {
        var companies: [String: Company] = [:]
        var byDomain: [String: (company: String, category: TrackerCategory)] = [:]
        var domains: [String: [String]] = [:]
        for row in rows {
            companies[row.id] = Company(id: row.id, name: row.name)
            for d in row.domains {
                byDomain[d] = (row.id, row.category)
                domains[row.id, default: []].append(d)
            }
        }
        self.companies = companies
        self.byDomain = byDomain
        domainsByCompany = domains.mapValues { $0.sorted() }
    }

    /// The company behind `host` and what that host is for; nil when the directory doesn't know it.
    public func match(host: String) -> Match? {
        var rest = Substring(host.lowercased())
        while rest.contains(".") {
            if let hit = byDomain[String(rest)], let company = companies[hit.company] {
                return Match(company: company, category: hit.category, domain: String(rest))
            }
            guard let dot = rest.firstIndex(of: ".") else { break }
            rest = rest[rest.index(after: dot)...]
        }
        return nil
    }

    public func company(_ id: String) -> Company? { companies[id] }

    /// Every domain the directory lists for a company, sorted.
    public func domains(of company: String) -> [String] { domainsByCompany[company] ?? [] }

    /// What the company's domains are for, worst first.
    public func categories(of company: String) -> [TrackerCategory] {
        Array(Set(domains(of: company).compactMap { byDomain[$0]?.category })).sorted()
    }

    public var companyCount: Int { companies.count }
    public var domainCount: Int { byDomain.count }
}

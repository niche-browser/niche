import Foundation

/// How much Shields does on a page: uBlock Origin Lite's four filtering modes, with their
/// meanings. One for every site (Settings ▸ Privacy, never `none`: the switches turn Shields
/// off) and, in the privacy panel, one for a site that needs something else.
///
/// - `none`: nothing is blocked, hidden or changed there.
/// - `basic`: requests the lists name are blocked. The page itself is left alone.
/// - `optimal`: also what the lists say about that site: its leftovers are hidden and the lists'
///   scripts run there (they answer a cookie notice, take the ads out of a video player's data,
///   defuse an "ad blocker detected" wall). uBlock Origin Lite's default, and Niche's.
/// - `complete`: also the generic hiding rules, matched against every page's own class and id
///   names. Hides more, costs a little on each page, and now and then hides something it shouldn't.
public enum FilteringMode: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0, basic, optimal, complete

    /// The one a new copy of Niche starts with.
    public static let standard = FilteringMode.optimal
    /// The ones a mode for every site can be.
    public static let forEverySite: [FilteringMode] = [.basic, .optimal, .complete]

    public static func < (a: FilteringMode, b: FilteringMode) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .none: "Off"
        case .basic: "Basic"
        case .optimal: "Optimal"
        case .complete: "Complete"
        }
    }

    /// One line under the slider.
    public var detail: String {
        switch self {
        case .none: "Nothing is blocked or hidden here."
        case .basic: "Ads and trackers are blocked on the network. Pages are left as they are."
        case .optimal: "Also hides what ads leave behind and fixes sites that fight ad blockers."
        case .complete: "Also hides anything that looks like an ad on any page. A few pages may lose something."
        }
    }

    /// Requests the lists name are blocked.
    public var blocksRequests: Bool { self >= .basic }
    /// What the lists say about the page's own site: its selectors are hidden and its scripts run.
    public var appliesSiteRules: Bool { self >= .optimal }
    /// The generic hiding rules, matched against the page's class and id names.
    public var hidesGenerically: Bool { self >= .complete }

    /// A value read from a file or a debug hook: unknown numbers are the standard mode.
    public init(stored: Int?) { self = stored.flatMap(FilteringMode.init(rawValue:)) ?? .standard }

    /// The word a debug hook takes ("off", "basic", "optimal", "complete").
    public init?(word: String) {
        switch word.lowercased() {
        case "off", "none": self = .none
        case "basic": self = .basic
        case "optimal": self = .optimal
        case "complete": self = .complete
        default: return nil
        }
    }
}

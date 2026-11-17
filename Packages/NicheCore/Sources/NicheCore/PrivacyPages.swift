import Foundation

/// The ledgers of one tab: the page on screen and the few before it, so going back to a page
/// (which asks for nothing again when the browser kept it whole) shows what that page did, not
/// what the page after it did. A page is named by a key the engine gives its address
/// (`NichePrivacyEvent.pageKey`); a page whose address changes without a new load (a redirect on
/// the way in, a single-page app moving on) keeps its ledger under every address it had.
public struct PrivacyPages: Equatable, Sendable {
    public struct Page: Equatable, Sendable {
        public var keys: Set<UInt64>
        public var ledger: PrivacyLedger
    }

    /// Oldest first; the last is the page asked for most recently.
    public private(set) var pages: [Page] = []
    /// Pages kept per tab.
    public static let limit = 6

    public init() {}

    /// Records an event that happened on the page `pageKey` of `pageSite`. Returns how many
    /// requests it added to that page's blocked count (0 or 1).
    @discardableResult
    public mutating func record(_ event: PrivacyEvent, pageKey: UInt64, pageSite: String, directory: TrackerDirectory = .standard) -> Int {
        if event.kind == .navigation {
            // The same page asked for again (a reload) starts over.
            pages.removeAll { $0.keys.contains(pageKey) }
            pages.append(Page(keys: [pageKey], ledger: PrivacyLedger(pageSite: pageSite, started: event.at)))
            if pages.count > Self.limit { pages.removeFirst(pages.count - Self.limit) }
            return 0
        }
        let i = index(pageKey: pageKey, pageSite: pageSite, at: event.at)
        let before = pages[i].ledger.summary.blockedRequests
        pages[i].ledger.record(event, directory: directory)
        return max(0, pages[i].ledger.summary.blockedRequests - before)
    }

    /// The ledger of the page `pageKey` of `site`: its own; else the latest of that site (an
    /// address the engine never announced); else an empty one.
    public func ledger(pageKey: UInt64, site: String) -> PrivacyLedger {
        if let page = pages.last(where: { $0.keys.contains(pageKey) }) { return page.ledger }
        if let page = pages.last(where: { $0.ledger.pageSite == site }) { return page.ledger }
        return PrivacyLedger(pageSite: site)
    }

    private mutating func index(pageKey: UInt64, pageSite: String, at: Date) -> Int {
        if let i = pages.lastIndex(where: { $0.keys.contains(pageKey) }) { return i }
        if let last = pages.indices.last {
            // The page moved to another address of its site without a load.
            if pages[last].ledger.pageSite == pageSite {
                pages[last].keys.insert(pageKey)
                return last
            }
            // Asked for on one site and answered on another (a short link): the same load.
            if !pages[last].touched {
                pages[last].keys.insert(pageKey)
                pages[last].ledger.reset(pageSite: pageSite, at: pages[last].ledger.started)
                return last
            }
        }
        // A page nobody announced (restored, or opened before Niche listened).
        pages.append(Page(keys: [pageKey], ledger: PrivacyLedger(pageSite: pageSite, started: at)))
        if pages.count > Self.limit { pages.removeFirst(pages.count - Self.limit) }
        return pages.count - 1
    }
}

private extension PrivacyPages.Page {
    /// Something happened on it since it was asked for.
    var touched: Bool { !ledger.isEmpty }
}

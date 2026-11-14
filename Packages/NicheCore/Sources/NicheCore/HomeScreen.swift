import Foundation

/// What a window shows while no tab is open: Niche's mark, a field that opens the command bar, and
/// the pages last closed in this space, to pick up from. 13 Nov 2026: an empty window was a blank
/// gradient with nothing to do in it.
public enum HomeScreen {
    /// A page to pick up again.
    public struct Recent: Equatable, Identifiable, Sendable {
        /// The archived tab it restores.
        public var id: UUID
        public var title: String
        /// The address without its scheme, `www.` and a trailing slash.
        public var address: String
        public var url: String

        public init(id: UUID, title: String, address: String, url: String) {
            self.id = id
            self.title = title
            self.address = address
            self.url = url
        }
    }

    /// The most the home lists: a glance, not a history.
    public static let recentLimit = 4

    /// The archived tabs to offer, newest first as given: web pages only, each page once (the
    /// newest of the tabs that had it), `recentLimit` at most.
    public static func recents(_ archived: [ArchivedItem]) -> [Recent] {
        var seen: Set<String> = [], out: [Recent] = []
        for entry in archived {
            guard out.count < recentLimit, let tab = entry.item.tab, tab.url.hasPrefix("http"),
                  seen.insert(CommandBarDedupe.comparableURL(tab.url)).inserted else { continue }
            let address = CommandBarDedupe.completionAddress(tab.url)
            let title = entry.item.title.flatMap { $0.isEmpty ? nil : $0 } ?? (tab.savedTitle.isEmpty ? address : tab.savedTitle)
            out.append(Recent(id: entry.id, title: title, address: address, url: tab.url))
        }
        return out
    }
}

import Foundation

/// Add Split View opens an empty pane with the command bar ready to fill it. A row that is an
/// open tab fills that pane too, instead of switching away from the split (reported 13 Nov 2026:
/// picking a favorite showed the favorite alone and left the pane empty).
public enum SplitPaneFill: Equatable, Sendable {
    /// The tab itself becomes the pane, with its page as it is.
    case joins
    /// The tab stays where it is; the pane opens its address.
    case opensAddress

    /// - Parameters:
    ///   - paneOfThisSplit: the tab is already a pane of the split being filled.
    ///   - pinned: the tab is a favorite or a pinned tab, which a split never takes away
    ///     (`SidebarStore.addToSplit` copies those too).
    ///   - sameSpace: the tab is in the space the split is in. Nothing changes space unasked.
    public static func fill(paneOfThisSplit: Bool, pinned: Bool, sameSpace: Bool) -> SplitPaneFill {
        !paneOfThisSplit && !pinned && sameSpace ? .joins : .opensAddress
    }

    /// What an open tab's row says it does, at the row's trailing edge.
    public static func rowHint(fillingPane: Bool) -> String {
        fillingPane ? "Open in Split" : "Switch to Tab"
    }
}
